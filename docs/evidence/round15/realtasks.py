#!/usr/bin/env python3
"""Does this model write code that RUNS, on tasks shaped like real work?

HumanEval says 82.3%, but that number is suspect three ways: it is a 2021
benchmark that is almost certainly in training data, it was scored at
temperature 0 while this server runs 0.6, and its problems are single small
functions. On one multi-class task the model produced code calling a method it
never defined.

So this measures the thing that actually matters: at the PRODUCTION temperature,
on multi-part tasks, does the generated code execute and pass its own tests?
Each task ships an independent check that the harness appends -- the model never
sees it, so it cannot satisfy the test by writing the test.
"""
import json, re, subprocess, sys, tempfile, os, time, urllib.request

URL = "http://LLAMA_HOST:12345/v1/chat/completions"
TEMP = 0.6          # production sampling, not greedy
REPEATS = int(sys.argv[1]) if len(sys.argv) > 1 else 2

TASKS = [
    ("lru_ttl",
     "Implementa en Python una clase LRUCache con esta firma EXACTA: "
     "class LRUCache: def __init__(self, capacity, ttl). Metodos: get(key) devuelve None si no esta "
     "o si caduco, put(key, value), y __len__. Expulsa por LRU al superar capacity y "
     "las entradas con mas de ttl segundos no se devuelven.",
     """
import time as _t
c = LRUCache(2, ttl=100)
c.put('a', 1); c.put('b', 2)
assert c.get('a') == 1
c.put('c', 3)                      # debe expulsar a 'b' (LRU)
assert c.get('b') is None
assert len(c) == 2
d = LRUCache(2, ttl=0.05)
d.put('x', 9); _t.sleep(0.12)
assert d.get('x') is None          # caducado
"""),
    ("retry",
     "Escribe un decorador Python con esta firma EXACTA: retry(times, exceptions, base_delay). "
     "Reintenta la funcion hasta 'times' veces en total, con backoff exponencial partiendo de "
     "base_delay segundos, capturando solo las excepciones de la tupla 'exceptions', "
     "y relanza la ultima si se agotan los intentos.",
     """
calls = {'n': 0}
@retry(times=3, exceptions=(ValueError,), base_delay=0.001)
def flaky():
    calls['n'] += 1
    if calls['n'] < 3: raise ValueError('boom')
    return 'ok'
assert flaky() == 'ok'
assert calls['n'] == 3
calls2 = {'n': 0}
@retry(times=2, exceptions=(ValueError,), base_delay=0.001)
def always():
    calls2['n'] += 1
    raise ValueError('nope')
try:
    always(); assert False, 'deberia relanzar'
except ValueError: pass
assert calls2['n'] == 2
"""),
    ("csv_group",
     "Escribe una funcion Python agrupar_ventas(filas) que recibe una lista de dicts con "
     "claves 'region', 'producto' e 'importe' (string con coma decimal, p.ej. '1.234,50') "
     "y devuelve un dict {region: {producto: total_float}} con los importes sumados.",
     """
filas = [
  {'region':'norte','producto':'A','importe':'1.234,50'},
  {'region':'norte','producto':'A','importe':'10,50'},
  {'region':'norte','producto':'B','importe':'5,00'},
  {'region':'sur','producto':'A','importe':'2,25'},
]
r = agrupar_ventas(filas)
assert abs(r['norte']['A'] - 1245.00) < 0.01, r
assert abs(r['norte']['B'] - 5.00) < 0.01
assert abs(r['sur']['A'] - 2.25) < 0.01
"""),
    ("tokenizer",
     "Escribe una funcion Python tokenizar(expr) que convierta una expresion aritmetica "
     "en una lista de tokens (numeros como float, operadores y parentesis como strings), "
     "soportando decimales y numeros negativos unarios al inicio o tras un parentesis.",
     """
assert tokenizar('1+2') == [1.0,'+',2.0]
assert tokenizar('(-3.5)*2') == ['(',-3.5,')','*',2.0]
t = tokenizar('10/(2+3)')
assert t == [10.0,'/','(',2.0,'+',3.0,')'], t
"""),
    ("path_merge",
     "Escribe una funcion Python fusionar_config(base, override) que fusione dos dicts "
     "anidados en profundidad: las claves de override ganan, los dicts se fusionan "
     "recursivamente, y las listas se reemplazan enteras (no se concatenan).",
     """
b = {'a':1,'n':{'x':1,'y':2},'l':[1,2]}
o = {'n':{'y':9,'z':3},'l':[7]}
r = fusionar_config(b,o)
assert r['a'] == 1
assert r['n'] == {'x':1,'y':9,'z':3}, r['n']
assert r['l'] == [7]
assert b['n']['y'] == 2, 'no debe mutar el original'
"""),
]


def ask(prompt):
    body = json.dumps({"model": "llama-local",
                       "messages": [{"role": "user", "content": prompt + " Devuelve solo el codigo."}],
                       "temperature": TEMP}).encode()   # no max_tokens: like OpenCode
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=1800) as r:
        return json.loads(r.read())


def extract(t):
    m = re.findall(r"```(?:python)?\n(.*?)```", t, re.S)
    return max(m, key=len) if m else t


print(f"temperatura={TEMP} (produccion) | repeticiones={REPEATS} | sin max_tokens, como OpenCode\n")
print(f"{'tarea':12} {'intento':>7} {'tok/s':>7} {'seg':>6} {'resultado':>12}  detalle")
tot_ok = tot = 0
for name, prompt, check in TASKS:
    for k in range(1, REPEATS + 1):
        t0 = time.time()
        try:
            d = ask(prompt)
        except Exception as e:
            print(f"{name:12} {k:>7} {'-':>7} {'-':>6} {'HTTP_FALLO':>12}  {type(e).__name__}")
            tot += 1
            continue
        el = time.time() - t0
        ch = d["choices"][0]
        sp = round(d.get("timings", {}).get("predicted_per_second", 0), 1)
        code = extract(ch["message"].get("content") or "")
        tot += 1
        if not code.strip():
            print(f"{name:12} {k:>7} {sp:>7} {el:>6.0f} {'VACIA':>12}  finish={ch.get('finish_reason')}")
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False) as f:
            f.write(code + "\n\n# --- comprobacion independiente ---\n" + check)
            path = f.name
        try:
            r = subprocess.run(["python3", path], capture_output=True, timeout=60)
            ok = r.returncode == 0
            err = r.stderr.decode(errors="replace").strip().splitlines()
            detail = "" if ok else (err[-1][:60] if err else "sin stderr")
        except subprocess.TimeoutExpired:
            ok, detail = False, "TIMEOUT"
        finally:
            os.unlink(path)
        tot_ok += int(ok)
        print(f"{name:12} {k:>7} {sp:>7} {el:>6.0f} {'PASA' if ok else 'FALLA':>12}  {detail}")

print(f"\nRESULTADO: {tot_ok}/{tot} ({round(100*tot_ok/tot)}%) tareas reales con codigo que ejecuta y pasa sus tests")
print(f"Referencia HumanEval+ (temp 0, benchmark publico): 82.3%")

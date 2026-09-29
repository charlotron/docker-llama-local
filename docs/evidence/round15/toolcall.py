#!/usr/bin/env python3
"""Tool-calling reliability, hard edition -- a GATING test.

v1 scored 5/5 on the first pass, which means it measured nothing: a test every
candidate passes cannot rank candidates. These cases target the failures that
actually break a document agent, and that an easy test hides:

  simple        one obvious tool                         (sanity floor)
  selection     4 tools, one correct
  args_exact    numeric arg must survive verbatim
  args_multi    3 required args buried in messy prose
  trap          prose that LOOKS like tool A, needs tool B
  chain         needs tool 1, then tool 2 using its result
  multiturn     given a tool RESULT, use it -- do not re-call
  abstain       no tool applies -- answering is correct
  abstain_hard  sounds tool-ish but is general knowledge
  long_ctx      correct call after ~8K tokens of document noise

Scored per case so a model can fail one mode and pass others -- a single
pass/fail number would hide exactly the information needed to choose.
"""
import json, sys, urllib.request

URL = "http://127.0.0.1:12345/v1/chat/completions"
LABEL = sys.argv[1] if len(sys.argv) > 1 else "unnamed"
REPEATS = int(sys.argv[2]) if len(sys.argv) > 2 else 5
RES = "${HOME}/toolcall_results.txt"

def fn(name, desc, props, req):
    return {"type": "function", "function": {"name": name, "description": desc,
            "parameters": {"type": "object", "properties": props, "required": req}}}

TOOLS = [
    fn("buscar_documento", "Busca documentos por texto en el archivo del usuario.",
       {"consulta": {"type": "string"}, "anio": {"type": "integer"}}, ["consulta"]),
    fn("leer_documento", "Lee el contenido completo de un documento concreto por su id.",
       {"doc_id": {"type": "string"}}, ["doc_id"]),
    fn("enviar_email", "Envia un correo electronico.",
       {"destinatario": {"type": "string"}, "asunto": {"type": "string"},
        "cuerpo": {"type": "string"}}, ["destinatario", "asunto", "cuerpo"]),
    fn("crear_evento", "Crea un evento en el calendario.",
       {"titulo": {"type": "string"}, "fecha": {"type": "string", "description": "YYYY-MM-DD"}},
       ["titulo", "fecha"]),
    fn("convertir_moneda", "Convierte un importe entre divisas.",
       {"importe": {"type": "number"}, "origen": {"type": "string"}, "destino": {"type": "string"}},
       ["importe", "origen", "destino"]),
]

NOISE = "\n".join(
    f"Linea {i:05d}: nota interna de archivo, expediente {i % 97}, sin relevancia."
    for i in range(2400))


def args_of(tc):
    return json.loads(tc["function"]["arguments"])


def name_is(tc, n):
    return tc and tc[0]["function"]["name"] == n


CASES = [
    ("simple", [{"role": "user", "content": "Busca mis documentos sobre presupuestos."}],
     lambda tc, txt: name_is(tc, "buscar_documento")),

    ("selection", [{"role": "user", "content":
        "Apunta en mi calendario la revision anual para el 15 de marzo de 2027."}],
     lambda tc, txt: name_is(tc, "crear_evento") and args_of(tc[0]).get("fecha") == "2027-03-15"),

    ("args_exact", [{"role": "user", "content": "Convierte 1250.50 euros a yenes japoneses."}],
     lambda tc, txt: name_is(tc, "convertir_moneda")
                     and abs(args_of(tc[0]).get("importe", 0) - 1250.50) < 0.001),

    ("args_multi", [{"role": "user", "content":
        "Oye, escribele a marta.lopez@acme.es que el informe trimestral ya esta listo; "
        "ponle de asunto 'Informe Q3 cerrado' y en el cuerpo dile que lo revise antes del viernes."}],
     lambda tc, txt: name_is(tc, "enviar_email")
                     and args_of(tc[0]).get("destinatario") == "marta.lopez@acme.es"
                     and "Q3" in (args_of(tc[0]).get("asunto") or "")),

    # Mentions "correo" and a person, but the ACTION is a calendar entry.
    ("trap", [{"role": "user", "content":
        "Me ha escrito un correo Javier proponiendo la reunion de cierre. "
        "Metela en el calendario el 3 de febrero de 2027, titulo 'Reunion de cierre'."}],
     lambda tc, txt: name_is(tc, "crear_evento")),

    # Must search first; reading requires an id it does not have yet.
    ("chain", [{"role": "user", "content":
        "Encuentra mi documento del contrato Acme y dime que dice la clausula de rescision."}],
     lambda tc, txt: name_is(tc, "buscar_documento")),

    ("multiturn", [
        {"role": "user", "content": "Busca mis documentos sobre el contrato Acme."},
        {"role": "assistant", "tool_calls": [{"id": "c1", "type": "function", "function": {
            "name": "buscar_documento", "arguments": '{"consulta": "contrato Acme"}'}}]},
        {"role": "tool", "tool_call_id": "c1",
         "content": '{"resultados": [{"titulo": "Acme-2024.pdf", "doc_id": "D-771", "paginas": 12}]}'}],
     lambda tc, txt: (not tc) and "Acme-2024" in txt),

    ("abstain", [{"role": "user", "content": "Cuantos lados tiene un hexagono?"}],
     lambda tc, txt: (not tc) and ("6" in txt or "seis" in txt.lower())),

    # Sounds like currency, but is a general-knowledge question.
    ("abstain_hard", [{"role": "user", "content":
        "Que moneda se usa en Japon y desde cuando existe el yen?"}],
     lambda tc, txt: (not tc) and ("yen" in txt.lower())),

    ("long_ctx", [{"role": "user", "content":
        NOISE + "\n\nDejando de lado el archivo anterior: busca mis documentos sobre "
                "'auditoria energetica' del ano 2025."}],
     lambda tc, txt: name_is(tc, "buscar_documento")
                     and args_of(tc[0]).get("anio") == 2025),
]


def ask(messages):
    body = json.dumps({"model": "llama-local", "messages": messages, "tools": TOOLS,
                       "max_tokens": 32768, "temperature": 0.6}).encode()
    req = urllib.request.Request(URL, data=body, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=1800) as r:
        return json.loads(r.read())


out = open(RES, "a")
print(f"{'caso':14} {'ok':>5}      fallos")
totals = {}
for name, msgs, check in CASES:
    ok, fails = 0, []
    for _ in range(REPEATS):
        try:
            d = ask(msgs)
        except Exception as e:
            fails.append(f"HTTP:{type(e).__name__}")
            continue
        m = d["choices"][0]["message"]
        tc = m.get("tool_calls") or []
        txt = m.get("content") or ""
        bad = False
        for c in tc:
            try:
                json.loads(c["function"]["arguments"])
            except Exception:
                bad = True
        if bad:
            fails.append("JSON_INVALIDO")
            continue
        try:
            good = bool(check(tc, txt))
        except Exception:
            good = False
        if good:
            ok += 1
        else:
            fails.append(f"llamo:{tc[0]['function']['name'] if tc else 'ninguna'}")
    totals[name] = ok
    out.write(f"{LABEL} | {name} | {ok}/{REPEATS} | {','.join(fails[:4])}\n")
    out.flush()
    print(f"{name:14} {ok:>2}/{REPEATS}      {','.join(fails[:4])}")

tot, mx = sum(totals.values()), len(CASES) * REPEATS
out.write(f"{LABEL} | TOTAL | {tot}/{mx} ({round(100*tot/mx)}%)\n")
out.flush()
print(f"\n{LABEL} | TOTAL | {tot}/{mx} ({round(100*tot/mx)}%)")

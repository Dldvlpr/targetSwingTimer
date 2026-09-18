# Target Swing Timer. Copyright (C) 2026 les auteurs de Target Swing Timer. GPL-2.0-or-later, voir LICENSE.
"""Extrait (entry, BaseAttackTime) de la table creature_template d'un dump SQL MySQL.
Usage : extract.py <dump.sql|dump.sql.gz> <sortie.tsv>
"""
import gzip, re, sys

ATTACK_COLS = ("BaseAttackTime", "MeleeBaseAttackTime", "baseattacktime")

def open_any(path):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace") if path.endswith(".gz") \
        else open(path, encoding="utf-8", errors="replace")

def tuples(s):
    """Découpe le corps d'un INSERT ... VALUES (...),(...); en listes de champs bruts."""
    i, n = 0, len(s)
    while i < n:
        if s[i] != "(":
            i += 1
            continue
        i += 1
        fields, cur, depth = [], [], 0
        while i < n:
            c = s[i]
            if c == "'":
                j = i + 1
                while True:
                    if s[j] == "\\":
                        j += 2
                    elif s[j] == "'":
                        if j + 1 < n and s[j + 1] == "'":
                            j += 2
                        else:
                            break
                    else:
                        j += 1
                cur.append(s[i:j + 1])
                i = j + 1
            elif c == "," and depth == 0:
                fields.append("".join(cur).strip()); cur = []
                i += 1
            elif c == "(":
                depth += 1; cur.append(c); i += 1
            elif c == ")":
                if depth == 0:
                    fields.append("".join(cur).strip())
                    i += 1
                    break
                depth -= 1; cur.append(c); i += 1
            else:
                cur.append(c); i += 1
        yield fields

def main(src, dst):
    cols, in_create = [], False
    out, seen = {}, 0
    pending, pending_explicit = None, None
    create_re = re.compile(r"CREATE TABLE\s+`?creature_template`?\s*\(", re.I)
    insert_re = re.compile(r"INSERT\s+(?:IGNORE\s+)?INTO\s+`?creature_template`?\s*(\([^)]*\))?\s*VALUES\s*(.*)", re.I | re.S)
    col_re = re.compile(r"^\s*`([^`]+)`")
    for line in open_any(src):
        if in_create:
            m = col_re.match(line)
            if m:
                cols.append(m.group(1))
            elif line.strip().startswith(")") or line.strip().upper().startswith(("PRIMARY", "KEY", "UNIQUE", "INDEX", "CONSTRAINT")):
                if line.strip().startswith(")"):
                    in_create = False
            continue
        if create_re.search(line):
            in_create = True
            cols = []
            continue
        if pending is not None:
            pending.append(line)
            if not line.rstrip().endswith(";"):
                continue
            body, explicit = "".join(pending), pending_explicit
            pending = None
        else:
            m = insert_re.search(line)
            if not m:
                continue
            explicit = m.group(1)
            if not line.rstrip().endswith(";"):
                pending, pending_explicit = [m.group(2)], explicit
                continue
            body = m.group(2)
        names = [c.strip("` ") for c in explicit.strip("()").split(",")] if explicit else cols
        if not names:
            sys.exit("colonnes inconnues avant INSERT")
        idx_entry = next(i for i, c in enumerate(names) if c.lower() == "entry")
        idx_att = next((i for i, c in enumerate(names) if c in ATTACK_COLS or c.lower() == "baseattacktime"), None)
        if idx_att is None:
            sys.exit("colonne BaseAttackTime introuvable : %s" % names)
        for f in tuples(body):
            if len(f) != len(names):
                continue
            try:
                entry, att = int(f[idx_entry]), int(f[idx_att])
            except ValueError:
                continue
            seen += 1
            out[entry] = att
    with open(dst, "w") as fh:
        for k in sorted(out):
            fh.write("%d\t%d\n" % (k, out[k]))
    print(src, "lignes", seen, "entrées", len(out), "colonnes", len(cols) or "explicites")

if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])

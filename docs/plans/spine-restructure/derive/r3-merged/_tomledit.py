# Block-level editor for the spine TOML carriers: keeps every untouched line
# byte for byte, rewrites only the cells an edit names, and inserts new rows.
# Used by _r3b_apply.py.
import re
import tomllib

HDR = re.compile(r'^\[([a-z_]+)\.([A-Za-z0-9-]+)\]\s*$')
KEY = re.compile(r'^([A-Za-z_][A-Za-z0-9_]*) = ')
CURLY = {'‘': "'", '’': "'", '“': '"', '”': '"', '–': '-', '—': '-'}


def ascii_quotes(s):
    for k, v in CURLY.items():
        s = s.replace(k, v)
    return s


class Row:
    def __init__(self, table, rid):
        self.table, self.id = table, rid
        self.cells = []  # [key, raw_text]
        self.touched = False

    def _idx(self, key):
        for i, (k, _) in enumerate(self.cells):
            if k == key:
                return i
        return None

    def get(self, key):
        i = self._idx(key)
        if i is None:
            return None
        return tomllib.loads(self.cells[i][1])[key]

    def raw_style(self, key):
        i = self._idx(key)
        return None if i is None else self.cells[i][1][len(key) + 3:].startswith('"""')


def enc_str(s, triple):
    s = ascii_quotes(s)
    if triple:
        body = s.replace('\\', '\\\\').replace('"""', '""\\"')
        if body.endswith('"'):
            body = body[:-1] + '\\"'
        return '"""' + body + '"""'
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'


def enc(key, value, triple=None):
    if isinstance(value, list):
        return f'{key} = [' + ', '.join(enc_str(v, False) for v in value) + ']'
    if triple is None:
        triple = len(value) > 90 or '"' in value or '\n' in value
    return f'{key} = ' + enc_str(value, triple)


class Doc:
    def __init__(self, text):
        self.segs = []  # str (raw lines) or Row
        self.rows = {}
        lines = text.split('\n')
        i, cur = 0, None
        raw = []
        while i < len(lines):
            line = lines[i]
            m = HDR.match(line)
            if m:
                if raw:
                    self.segs.append('\n'.join(raw)); raw = []
                cur = Row(m.group(1), m.group(2))
                self.segs.append(cur); self.rows[cur.id] = cur
                i += 1
                continue
            km = KEY.match(line) if cur is not None else None
            if km:
                key = km.group(1)
                buf = [line]
                rest = line[len(key) + 3:]
                if rest.startswith('"""') and rest.count('"""') == 1:
                    i += 1
                    while '"""' not in lines[i]:
                        buf.append(lines[i]); i += 1
                    buf.append(lines[i])
                cur.cells.append([key, '\n'.join(buf)])
                i += 1
                continue
            cur = None
            raw.append(line)
            i += 1
        if raw:
            self.segs.append('\n'.join(raw))

    def row(self, rid):
        return self.rows[rid]

    def set(self, rid, key, value, after=None, triple=None):
        r = self.rows[rid]
        r.touched = True
        if triple is None and isinstance(value, str):
            st = r.raw_style(key)
            triple = st if st is not None else None
        text = enc(key, value, triple)
        i = r._idx(key)
        if i is not None:
            r.cells[i][1] = text
            return
        if after is not None:
            j = r._idx(after)
            assert j is not None, (rid, after)
            r.cells.insert(j + 1, [key, text])
            return
        j = r._idx('status')
        if j is None:
            r.cells.append([key, text])
        else:
            r.cells.insert(j, [key, text])

    def sub(self, rid, key, old, new, count=1):
        v = self.rows[rid].get(key)
        assert v is not None, (rid, key)
        n = v.count(old)
        assert n == count, f'{rid}.{key}: {n} occurrences of {old!r}'
        self.set(rid, key, v.replace(old, new))

    def delete(self, rid, key):
        r = self.rows[rid]
        i = r._idx(key)
        assert i is not None, (rid, key)
        del r.cells[i]
        r.touched = True

    def add_row(self, after_rid, table, rid, items):
        assert rid not in self.rows, rid
        r = Row(table, rid)
        r.touched = True
        for k, v in items:
            r.cells.append([k, enc(k, v)])
        pos = self.segs.index(self.rows[after_rid])
        self.segs.insert(pos + 1, '')
        self.segs.insert(pos + 2, r)
        self.rows[rid] = r

    def text(self):
        out = []
        for s in self.segs:
            if isinstance(s, Row):
                out.append(f'[{s.table}.{s.id}]')
                out.extend(c[1] for c in s.cells)
            else:
                out.append(s)
        return '\n'.join(out)

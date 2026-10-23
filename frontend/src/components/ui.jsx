export function Panel({ title, action, children }) {
  return (
    <section className="panel">
      {(title || action) && (
        <header className="panel-head">
          <h2>{title}</h2>
          {action}
        </header>
      )}
      {children}
    </section>
  )
}

export function Status({ value }) {
  return <span className={`tag tag-${String(value).toLowerCase()}`}>{value}</span>
}

export function Message({ result }) {
  if (!result) return null
  return (
    <div className={`msg ${result.ok ? 'msg-ok' : 'msg-err'}`} role="status">
      {result.ok ? '✓ ' : '✕ '}
      {result.text}
      {result.code && <span className="mono muted"> {result.code}</span>}
    </div>
  )
}

export function Loading({ error, loading }) {
  if (error) return <p className="msg msg-err">{error}</p>
  if (loading) return <p className="muted">Loading…</p>
  return null
}

export function Table({ columns, rows, empty = 'No rows' }) {
  if (!rows?.length) return <p className="muted">{empty}</p>
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>{columns.map((c) => <th key={c.key} className={c.num ? 'num' : ''}>{c.label}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((r, i) => (
            <tr key={i}>
              {columns.map((c) => (
                <td key={c.key} className={c.num ? 'num mono' : c.mono ? 'mono' : ''}>
                  {c.render ? c.render(r) : r[c.key]}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

export function AccountSelect({ accounts, value, onChange, label, onlyActive = false }) {
  const list = (accounts || []).filter((a) => !onlyActive || a.status === 'ACTIVE')
  return (
    <label>
      {label}
      <select value={value} onChange={(e) => onChange(e.target.value)} required>
        <option value="">Select account</option>
        {list.map((a) => (
          <option key={a.account_id} value={a.account_id}>
            {a.account_no} · {a.full_name} · {a.status}
          </option>
        ))}
      </select>
    </label>
  )
}

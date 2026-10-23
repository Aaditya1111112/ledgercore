import { useApi } from '../hooks'
import { money, when } from '../api'
import { Loading, Panel, Status, Table } from './ui'

export default function Dashboard() {
  const summary = useApi('/reports/summary')
  const recent = useApi('/transactions?limit=15')
  const s = summary.data

  return (
    <>
      <Loading error={summary.error} loading={summary.loading && !s} />
      {s && (
        <div className="stats">
          <Stat label="Total balance held" value={`₹ ${money(s.total_balance)}`} big />
          <Stat label="Customers" value={s.customers} />
          <Stat label="Accounts (active)" value={`${s.accounts} (${s.active_accounts})`} />
          <Stat label="Completed transactions" value={s.completed_transactions} />
          <Stat label="Rejected attempts" value={s.rejected_transactions} />
          <Stat
            label="Ledger reconciliation"
            value={s.unreconciled_accounts === 0 ? 'Balanced' : `${s.unreconciled_accounts} off`}
            tone={s.unreconciled_accounts === 0 ? 'good' : 'bad'}
          />
        </div>
      )}

      <Panel title="Recent transactions" action={<button className="ghost" onClick={recent.reload}>Refresh</button>}>
        <Loading error={recent.error} loading={recent.loading && !recent.data} />
        <Table
          rows={recent.data}
          columns={[
            { key: 'transaction_id', label: '#', mono: true },
            { key: 'transaction_type', label: 'Type' },
            { key: 'amount', label: 'Amount', num: true, render: (r) => money(r.amount) },
            { key: 'status', label: 'Status', render: (r) => <Status value={r.status} /> },
            { key: 'accounts', label: 'Ledger entries', mono: true, render: (r) => r.accounts || '—' },
            { key: 'description', label: 'Note', render: (r) => <span className="clip">{r.description}</span> },
            { key: 'created_at', label: 'Time', render: (r) => when(r.created_at) },
          ]}
        />
      </Panel>
    </>
  )
}

function Stat({ label, value, big, tone }) {
  return (
    <div className={`stat ${big ? 'stat-big' : ''} ${tone ? `stat-${tone}` : ''}`}>
      <div className="stat-label">{label}</div>
      <div className="stat-value mono">{value}</div>
    </div>
  )
}

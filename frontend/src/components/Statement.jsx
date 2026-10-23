import { useState } from 'react'
import { money, when } from '../api'
import { useApi } from '../hooks'
import { AccountSelect, Loading, Panel, Status, Table } from './ui'

export default function Statement() {
  const accounts = useApi('/accounts')
  const [id, setId] = useState('')
  const stmt = useApi(id ? `/accounts/${id}/statement` : null)
  const detail = useApi(id ? `/accounts/${id}` : null)
  const a = stmt.data?.account

  return (
    <>
      <Panel title="Account statement">
        <div className="form inline">
          <AccountSelect label="Account" accounts={accounts.data} value={id} onChange={setId} />
        </div>
        {id && <Loading error={stmt.error} loading={stmt.loading && !stmt.data} />}
        {a && (
          <div className="stmt-head">
            <div><span className="muted">Account</span><b className="mono">{a.account_no}</b></div>
            <div><span className="muted">Holder</span><b>{a.full_name}</b></div>
            <div><span className="muted">Status</span><Status value={a.status} /></div>
            <div><span className="muted">Transactions</span><b className="mono">{detail.data?.transaction_count ?? '…'}</b></div>
            <div><span className="muted">Balance</span><b className="mono big">₹ {money(a.balance)}</b></div>
          </div>
        )}
      </Panel>
      {a && (
        <Panel title="Ledger entries (newest first)">
          <Table
            rows={stmt.data.entries}
            empty="No entries yet"
            columns={[
              { key: 'created_at', label: 'Time', render: (r) => when(r.created_at) },
              { key: 'transaction_id', label: 'Txn', mono: true },
              { key: 'transaction_type', label: 'Type' },
              { key: 'description', label: 'Note' },
              { key: 'debit', label: 'Debit', num: true, render: (r) => r.entry_type === 'DEBIT' ? money(r.amount) : '' },
              { key: 'credit', label: 'Credit', num: true, render: (r) => r.entry_type === 'CREDIT' ? money(r.amount) : '' },
              { key: 'balance_after', label: 'Balance', num: true, render: (r) => money(r.balance_after) },
            ]}
          />
        </Panel>
      )}
    </>
  )
}

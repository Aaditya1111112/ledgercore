import { useState } from 'react'
import { money, when } from '../api'
import { useApi } from '../hooks'
import { Loading, Panel, Status, Table } from './ui'

const TABS = ['Monthly', 'High value', 'Reconciliation', 'Audit trail', 'Event log']

export default function Reports() {
  const [tab, setTab] = useState(TABS[0])
  return (
    <>
      <div className="seg wide">
        {TABS.map((t) => <button key={t} className={tab === t ? 'on' : ''} onClick={() => setTab(t)}>{t}</button>)}
      </div>
      {tab === 'Monthly' && <Monthly />}
      {tab === 'High value' && <HighValue />}
      {tab === 'Reconciliation' && <Reconciliation />}
      {tab === 'Audit trail' && <Audit />}
      {tab === 'Event log' && <Logs />}
    </>
  )
}

function Monthly() {
  const r = useApi('/reports/monthly')
  return (
    <Panel title="Completed activity by month">
      <Loading {...r} />
      <Table rows={r.data} columns={[
        { key: 'month', label: 'Month', mono: true },
        { key: 'transaction_type', label: 'Type' },
        { key: 'transaction_count', label: 'Count', num: true },
        { key: 'total_amount', label: 'Total', num: true, render: (x) => money(x.total_amount) },
      ]} />
    </Panel>
  )
}

function HighValue() {
  const [th, setTh] = useState(50000)
  const [applied, setApplied] = useState(50000)
  const r = useApi(`/reports/high-value?threshold=${applied}`)
  return (
    <Panel title="High-value transactions">
      <form className="form inline" onSubmit={(e) => { e.preventDefault(); setApplied(th) }}>
        <label>Threshold (₹)<input type="number" value={th} onChange={(e) => setTh(e.target.value)} /></label>
        <button type="submit">Apply</button>
      </form>
      <Loading {...r} />
      <Table rows={r.data} columns={[
        { key: 'transaction_id', label: '#', mono: true },
        { key: 'transaction_type', label: 'Type' },
        { key: 'amount', label: 'Amount', num: true, render: (x) => money(x.amount) },
        { key: 'accounts', label: 'Entries', mono: true },
        { key: 'created_at', label: 'Time', render: (x) => when(x.created_at) },
      ]} />
    </Panel>
  )
}

function Reconciliation() {
  const r = useApi('/reports/reconciliation')
  const bad = r.data?.filter((x) => x.difference !== 0).length
  return (
    <Panel title="Stored balance vs ledger (credits − debits)">
      {r.data && (
        <p className={`msg ${bad ? 'msg-err' : 'msg-ok'}`}>
          {bad ? `${bad} account(s) do not match` : `All ${r.data.length} accounts match their ledger`}
        </p>
      )}
      <Loading {...r} />
      <Table rows={r.data} columns={[
        { key: 'account_no', label: 'Account', mono: true },
        { key: 'stored_balance', label: 'Stored', num: true, render: (x) => money(x.stored_balance) },
        { key: 'ledger_balance', label: 'From ledger', num: true, render: (x) => money(x.ledger_balance) },
        { key: 'difference', label: 'Difference', num: true, render: (x) => money(x.difference) },
      ]} />
    </Panel>
  )
}

function Audit() {
  const r = useApi('/audit')
  return (
    <Panel title="ACCOUNT_AUDIT (written by trigger)">
      <Loading {...r} />
      <Table rows={r.data} columns={[
        { key: 'audit_id', label: '#', mono: true },
        { key: 'account_no', label: 'Account', mono: true },
        { key: 'old_balance', label: 'Old', num: true, render: (x) => money(x.old_balance) },
        { key: 'new_balance', label: 'New', num: true, render: (x) => money(x.new_balance) },
        { key: 'change', label: 'Change', num: true, render: (x) => (x.change > 0 ? '+' : '') + money(x.change) },
        { key: 'changed_by', label: 'DB user', mono: true },
        { key: 'changed_at', label: 'Time', render: (x) => when(x.changed_at) },
      ]} />
    </Panel>
  )
}

function Logs() {
  const r = useApi('/logs')
  return (
    <Panel title="TRANSACTION_LOG">
      <Loading {...r} />
      <Table rows={r.data} columns={[
        { key: 'log_id', label: '#', mono: true },
        { key: 'event_type', label: 'Event', render: (x) => <Status value={x.event_type} /> },
        { key: 'transaction_id', label: 'Txn', mono: true },
        { key: 'account_id', label: 'Acct', mono: true },
        { key: 'details', label: 'Details', render: (x) => <span className="clip wide">{x.details}</span> },
        { key: 'logged_at', label: 'Time', render: (x) => when(x.logged_at) },
      ]} />
    </Panel>
  )
}

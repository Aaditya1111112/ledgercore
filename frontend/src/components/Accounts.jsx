import { useState } from 'react'
import { api, money, when } from '../api'
import { useApi } from '../hooks'
import { Loading, Message, Panel, Status, Table } from './ui'

export default function Accounts() {
  const accounts = useApi('/accounts')
  const customers = useApi('/customers')
  const [result, setResult] = useState(null)

  const run = async (fn, okText) => {
    try {
      const r = await fn()
      setResult({ ok: true, text: okText(r) })
      accounts.reload()
      customers.reload()
    } catch (e) {
      setResult({ ok: false, text: e.message, code: e.code })
    }
  }

  const changeStatus = (a, status) =>
    run(() => api.patch(`/accounts/${a.account_id}/status`, { status }),
        () => `${a.account_no} is now ${status}`)

  return (
    <>
      <Message result={result} />
      <div className="grid-2">
        <NewCustomer onSubmit={(d) => run(() => api.post('/customers', d), (r) => `Customer #${r.customer_id} created`)} />
        <NewAccount
          customers={customers.data}
          onSubmit={(d) => run(() => api.post('/accounts', d), (r) => `Account ${r.account_no} opened`)}
        />
      </div>

      <Panel title="Accounts">
        <Loading error={accounts.error} loading={accounts.loading && !accounts.data} />
        <Table
          rows={accounts.data}
          columns={[
            { key: 'account_no', label: 'Account no', mono: true },
            { key: 'full_name', label: 'Holder' },
            { key: 'account_type', label: 'Type' },
            { key: 'balance', label: 'Balance', num: true, render: (r) => money(r.balance) },
            { key: 'status', label: 'Status', render: (r) => <Status value={r.status} /> },
            { key: 'opened_at', label: 'Opened', render: (r) => when(r.opened_at) },
            {
              key: 'actions', label: '', render: (a) => a.status === 'CLOSED' ? null : (
                <div className="row-actions">
                  {a.status === 'ACTIVE'
                    ? <button className="ghost" onClick={() => changeStatus(a, 'FROZEN')}>Freeze</button>
                    : <button className="ghost" onClick={() => changeStatus(a, 'ACTIVE')}>Unfreeze</button>}
                  <button className="ghost danger" onClick={() => changeStatus(a, 'CLOSED')}>Close</button>
                </div>
              ),
            },
          ]}
        />
      </Panel>
    </>
  )
}

function NewCustomer({ onSubmit }) {
  const [f, setF] = useState({ full_name: '', email: '', phone: '' })
  const set = (k) => (e) => setF({ ...f, [k]: e.target.value })
  return (
    <Panel title="New customer">
      <form className="form" onSubmit={(e) => { e.preventDefault(); onSubmit(f) }}>
        <label>Full name<input value={f.full_name} onChange={set('full_name')} required /></label>
        <label>Email<input type="email" value={f.email} onChange={set('email')} required /></label>
        <label>Phone<input value={f.phone} onChange={set('phone')} maxLength={15} /></label>
        <button type="submit">Create customer</button>
      </form>
    </Panel>
  )
}

function NewAccount({ customers, onSubmit }) {
  const [f, setF] = useState({ customer_id: '', account_type: 'SAVINGS' })
  return (
    <Panel title="Open account">
      <form className="form" onSubmit={(e) => { e.preventDefault(); onSubmit(f) }}>
        <label>Customer
          <select value={f.customer_id} onChange={(e) => setF({ ...f, customer_id: e.target.value })} required>
            <option value="">Select customer</option>
            {(customers || []).map((c) => (
              <option key={c.customer_id} value={c.customer_id}>{c.full_name} · {c.email}</option>
            ))}
          </select>
        </label>
        <label>Type
          <select value={f.account_type} onChange={(e) => setF({ ...f, account_type: e.target.value })}>
            <option>SAVINGS</option>
            <option>CURRENT</option>
          </select>
        </label>
        <button type="submit">Open account</button>
      </form>
    </Panel>
  )
}

import { useState } from 'react'
import { api, money } from '../api'
import { useApi } from '../hooks'
import { AccountSelect, Message, Panel } from './ui'

// The frontend checks almost nothing on purpose: every rule (positive
// amount, enough funds, ACTIVE status, no self-transfer) is enforced by
// the database, and its error message is shown here.
export default function Operations() {
  const accounts = useApi('/accounts')
  const [mode, setMode] = useState('deposit')
  const [f, setF] = useState({ account_id: '', destination: '', amount: '', description: '' })
  const [result, setResult] = useState(null)
  const [busy, setBusy] = useState(false)

  const set = (k) => (v) => setF({ ...f, [k]: v })

  const submit = async (e) => {
    e.preventDefault()
    setBusy(true)
    try {
      const body = mode === 'transfer'
        ? { source_account_id: f.account_id, destination_account_id: f.destination, amount: f.amount, description: f.description }
        : { account_id: f.account_id, amount: f.amount, description: f.description }
      const r = await api.post(`/transactions/${mode}`, body)
      setResult({ ok: true, text: `${mode} of ₹ ${money(f.amount)} completed. Transaction #${r.transaction_id}` })
      setF({ ...f, amount: '', description: '' })
      accounts.reload()
    } catch (err) {
      setResult({ ok: false, text: `Rejected: ${err.message}. Nothing was changed.`, code: err.code })
    } finally {
      setBusy(false)
    }
  }

  const selected = accounts.data?.find((a) => String(a.account_id) === String(f.account_id))

  return (
    <div className="ops">
      <Panel title="Money movement">
        <div className="seg" role="tablist">
          {['deposit', 'withdraw', 'transfer'].map((m) => (
            <button key={m} className={mode === m ? 'on' : ''} onClick={() => { setMode(m); setResult(null) }} type="button">
              {m}
            </button>
          ))}
        </div>
        <form className="form" onSubmit={submit}>
          <AccountSelect
            label={mode === 'transfer' ? 'From account' : 'Account'}
            accounts={accounts.data} value={f.account_id} onChange={set('account_id')}
          />
          {selected && <p className="hint mono">Current balance ₹ {money(selected.balance)}</p>}
          {mode === 'transfer' && (
            <AccountSelect label="To account" accounts={accounts.data} value={f.destination} onChange={set('destination')} />
          )}
          <label>Amount (₹)
            <input type="number" step="0.01" value={f.amount} onChange={(e) => set('amount')(e.target.value)} required />
          </label>
          <label>Description
            <input value={f.description} onChange={(e) => set('description')(e.target.value)} maxLength={200} />
          </label>
          <button type="submit" disabled={busy}>{busy ? 'Working…' : `Run ${mode}`}</button>
        </form>
        <Message result={result} />
      </Panel>

      <Panel title="What happens in the database">
        <ol className="explain">
          {mode === 'transfer' ? (
            <>
              <li>Savepoint set. Both rows locked with <code>SELECT … FOR UPDATE</code>, lower account id first.</li>
              <li>Checks: amount &gt; 0, not the same account, both ACTIVE, enough funds.</li>
              <li>Insert TRANSACTIONS + TRANSFER_DETAILS, debit source, credit destination, two ledger entries.</li>
              <li>Any failure rolls back to the savepoint: no partial debit. The rejection is logged by an autonomous transaction.</li>
              <li>Flask commits only when the whole procedure succeeded.</li>
            </>
          ) : (
            <>
              <li>Savepoint set. Account row locked with <code>SELECT … FOR UPDATE</code>.</li>
              <li>Checks: amount &gt; 0, account ACTIVE{mode === 'withdraw' ? ', enough funds' : ''}.</li>
              <li>Insert TRANSACTIONS, update balance, insert one {mode === 'deposit' ? 'CREDIT' : 'DEBIT'} ledger entry.</li>
              <li>The audit trigger records the old and new balance.</li>
              <li>Flask commits. On error it rolls back and shows the database message.</li>
            </>
          )}
        </ol>
        <p className="hint">Try an invalid one: a withdrawal larger than the balance, a frozen account, or a transfer to the same account.</p>
      </Panel>
    </div>
  )
}

import { useState } from 'react'
import Dashboard from './components/Dashboard'
import Accounts from './components/Accounts'
import Operations from './components/Operations'
import Statement from './components/Statement'
import Reports from './components/Reports'

const PAGES = {
  Dashboard,
  Accounts,
  Operations,
  Statement,
  Reports,
}

export default function App() {
  const [page, setPage] = useState('Dashboard')
  const Page = PAGES[page]
  return (
    <div className="shell">
      <aside className="side">
        <div className="brand">
          <span className="brand-mark">LC</span>
          <div>
            <div className="brand-name">LedgerCore</div>
            <div className="brand-sub">Oracle · PL/SQL ledger</div>
          </div>
        </div>
        <nav>
          {Object.keys(PAGES).map((p) => (
            <button key={p} className={p === page ? 'on' : ''} onClick={() => setPage(p)}>{p}</button>
          ))}
        </nav>
        <p className="side-note">Educational simulation. Fictional data only.</p>
      </aside>
      <main className="main">
        <h1>{page}</h1>
        <Page />
      </main>
    </div>
  )
}

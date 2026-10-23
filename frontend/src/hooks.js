import { useCallback, useEffect, useState } from 'react'
import { api } from './api'

// Loads a GET endpoint. Returns { data, error, loading, reload }.
export function useApi(path) {
  const [data, setData] = useState(null)
  const [error, setError] = useState(null)
  const [loading, setLoading] = useState(true)

  const reload = useCallback(() => {
    if (!path) return
    setLoading(true)
    api.get(path)
      .then((d) => { setData(d); setError(null) })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false))
  }, [path])

  useEffect(() => { reload() }, [reload])
  return { data, error, loading, reload }
}

import { useCallback, useEffect, useState } from 'react'
import { Activity, ArrowRight, CheckCircle2, CircleAlert, CircleUserRound, Cloud, KeyRound, LoaderCircle, LogOut, Plus, ShieldCheck, Trash2 } from 'lucide-react'
import { apiRequest } from './api.js'

function Brand() {
  return (
    <div className="brand">
      <div className="brand-mark"><ShieldCheck size={22} strokeWidth={2.1} /></div>
      <div><div className="brand-name">Zero Trust <span>Lab</span></div><div className="brand-caption">AWS · Secure application demo</div></div>
    </div>
  )
}

function ErrorNotice({ message }) {
  if (!message) return null
  return <div className="notice error" role="alert"><CircleAlert size={17} /><span>{message}</span></div>
}

function Login({ onLogin }) {
  const [username, setUsername] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  async function submit(event) {
    event.preventDefault()
    setError('')
    setBusy(true)
    try {
      const result = await apiRequest('/auth/login', { method: 'POST', body: { username, password } })
      // JWT remains in React memory only; it is deliberately not persisted to localStorage.
      onLogin(result.access_token)
    } catch (err) {
      setError(err.message || 'No se pudo iniciar sesión.')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="login-layout">
      <section className="login-story">
        <div className="eyebrow"><span className="eyebrow-dot" /> LABORATORIO DE SEGURIDAD</div>
        <h1>La confianza no se asume.<br /><em>Se verifica.</em></h1>
        <p>Una demostración de acceso seguro con identidad, autorización, conexiones cifradas y segmentación de red en AWS.</p>
        <div className="feature-list">
          <div><span className="feature-icon"><KeyRound size={17} /></span><span><strong>Identidad en cada petición</strong><small>JWT firmado y con expiración</small></span></div>
          <div><span className="feature-icon"><Cloud size={17} /></span><span><strong>Red segmentada</strong><small>Frontend público · API privada</small></span></div>
          <div><span className="feature-icon"><ShieldCheck size={17} /></span><span><strong>Cifrado de extremo a extremo</strong><small>HTTPS y TLS interno verificado</small></span></div>
        </div>
      </section>

      <section className="login-card" aria-labelledby="login-title">
        <div className="card-icon"><KeyRound size={22} /></div>
        <div className="card-kicker">ÁREA PROTEGIDA</div>
        <h2 id="login-title">Iniciar sesión</h2>
        <p className="muted">Usa las credenciales creadas en el servidor.</p>
        <ErrorNotice message={error} />
        <form onSubmit={submit}>
          <label htmlFor="username">Usuario</label>
          <input id="username" name="username" autoComplete="username" value={username} onChange={e => setUsername(e.target.value)} maxLength={64} required />
          <label htmlFor="password">Contraseña</label>
          <input id="password" name="password" type="password" autoComplete="current-password" value={password} onChange={e => setPassword(e.target.value)} required />
          <button className="primary-button" type="submit" disabled={busy}>
            {busy ? <><LoaderCircle size={17} className="spin" /> Verificando identidad…</> : <>Acceder al Dashboard <ArrowRight size={17} /></>}
          </button>
        </form>
        <div className="card-foot"><ShieldCheck size={15} /> Las rutas protegidas validan el token en el Backend.</div>
      </section>
    </main>
  )
}

function Dashboard({ token, onLogout }) {
  const [user, setUser] = useState(null)
  const [summary, setSummary] = useState(null)
  const [tasks, setTasks] = useState([])
  const [title, setTitle] = useState('')
  const [description, setDescription] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(true)
  const [saving, setSaving] = useState(false)

  const refresh = useCallback(async () => {
    const [me, dashboard, taskList] = await Promise.all([
      apiRequest('/auth/me', { token }),
      apiRequest('/dashboard', { token }),
      apiRequest('/tasks', { token }),
    ])
    setUser(me)
    setSummary(dashboard)
    setTasks(taskList)
  }, [token])

  useEffect(() => {
    let alive = true
    setBusy(true)
    refresh().catch(err => {
      if (alive) {
        setError(err.message)
        if (err.message.toLowerCase().includes('token') || err.message.toLowerCase().includes('sesión')) onLogout()
      }
    }).finally(() => { if (alive) setBusy(false) })
    return () => { alive = false }
  }, [refresh, onLogout])

  async function addTask(event) {
    event.preventDefault()
    if (!title.trim()) return
    setSaving(true)
    setError('')
    try {
      await apiRequest('/tasks', { token, method: 'POST', body: { title: title.trim(), description: description.trim() } })
      setTitle('')
      setDescription('')
      await refresh()
    } catch (err) { setError(err.message) }
    finally { setSaving(false) }
  }

  async function removeTask(taskId) {
    setError('')
    try {
      await apiRequest(`/tasks/${taskId}`, { token, method: 'DELETE' })
      setTasks(current => current.filter(task => task.id !== taskId))
      setSummary(current => current ? { ...current, task_count: Math.max(0, current.task_count - 1) } : current)
    } catch (err) { setError(err.message) }
  }

  return (
    <main className="dashboard-shell">
      <header className="topbar"><Brand /><div className="topbar-actions"><span className="secure-pill"><span /> Sesión autenticada</span><button className="ghost-button" onClick={onLogout}><LogOut size={16} /> Salir</button></div></header>
      <section className="dashboard-heading"><div><div className="eyebrow">PANEL DE CONTROL</div><h1>Tu espacio seguro.</h1><p>La API vuelve a comprobar tu identidad y permisos en cada solicitud.</p></div><div className="user-chip"><div className="avatar"><CircleUserRound size={21} /></div><div><strong>{user?.username || 'Verificando…'}</strong><small>{user?.role === 'admin' ? 'Administrador' : 'Usuario autenticado'}</small></div></div></section>
      <ErrorNotice message={error} />
      {busy ? <div className="loading-panel"><LoaderCircle className="spin" /> Verificando permisos y cargando recursos…</div> : <>
        <section className="stat-grid">
          <div className="stat-card"><div className="stat-top"><span>Estado de identidad</span><CheckCircle2 size={18} /></div><div className="stat-value">Verificado</div><div className="stat-detail">JWT válido · Bearer</div></div>
          <div className="stat-card"><div className="stat-top"><span>Conexión</span><ShieldCheck size={18} /></div><div className="stat-value">Cifrada</div><div className="stat-detail">HTTPS + TLS interno</div></div>
          <div className="stat-card"><div className="stat-top"><span>Recursos visibles</span><Activity size={18} /></div><div className="stat-value">{summary?.task_count ?? tasks.length}</div><div className="stat-detail">Filtrados por autorización</div></div>
        </section>
        <section className="content-grid">
          <div className="panel tasks-panel"><div className="panel-header"><div><h2>Recursos de prueba</h2><p>Los registros pertenecen al usuario autenticado; el administrador puede revisar todos.</p></div><span className="count-pill">{tasks.length}</span></div>
            <form className="task-form" onSubmit={addTask}><div className="input-row"><input value={title} onChange={e => setTitle(e.target.value)} placeholder="Título del recurso" aria-label="Título del recurso" maxLength={120} required /><button type="submit" className="primary-button compact" disabled={saving}><Plus size={17} /> Añadir</button></div><textarea value={description} onChange={e => setDescription(e.target.value)} placeholder="Descripción opcional" aria-label="Descripción del recurso" maxLength={2000} rows={2} /></form>
            {tasks.length === 0 ? <div className="empty-state"><div className="empty-icon"><Activity size={21} /></div><strong>Todavía no hay recursos</strong><span>Crea uno para comprobar la persistencia de datos protegida.</span></div> : <div className="task-list">{tasks.map(task => <article className="task-item" key={task.id}><div className="task-bullet"><CheckCircle2 size={17} /></div><div className="task-copy"><strong>{task.title}</strong>{task.description && <p>{task.description}</p>}<small>Propietario ID {task.owner_id}</small></div><button className="icon-button" aria-label={`Eliminar ${task.title}`} title="Eliminar recurso" onClick={() => removeTask(task.id)}><Trash2 size={16} /></button></article>)}</div>}
          </div>
          <aside className="panel posture-panel"><div className="panel-header"><div><h2>Controles activos</h2><p>Capas de protección del laboratorio</p></div></div><div className="control-list"><div><span className="control-check"><CheckCircle2 size={16} /></span><span><strong>Autenticación JWT</strong><small>Token firmado con expiración</small></span><span className="status-text">Activo</span></div><div><span className="control-check"><CheckCircle2 size={16} /></span><span><strong>Autorización por recurso</strong><small>Propiedad y rol revisados</small></span><span className="status-text">Activo</span></div><div><span className="control-check"><CheckCircle2 size={16} /></span><span><strong>Segmentación de red</strong><small>API sin dirección pública</small></span><span className="status-text">Activo</span></div><div><span className="control-check"><CheckCircle2 size={16} /></span><span><strong>Bloqueo de fuerza bruta</strong><small>Fail2Ban en el proxy</small></span><span className="status-text">Configurable</span></div></div><div className="zero-trust-note"><ShieldCheck size={19} /><p><strong>Verificar siempre.</strong> La interfaz no es la frontera de seguridad: el Backend aplica los controles de acceso.</p></div></aside>
        </section>
        <footer className="dashboard-footer"><span>Zero Trust Lab</span><span>Respuesta generada {summary?.generated_at ? new Date(summary.generated_at).toLocaleString() : '—'}</span></footer>
      </>}
    </main>
  )
}

export default function App() {
  const [token, setToken] = useState(null)
  const logout = useCallback(() => setToken(null), [])
  return <div className="app-shell"><div className="ambient ambient-one" /><div className="ambient ambient-two" />{token ? <Dashboard token={token} onLogout={logout} /> : <><header className="login-topbar"><Brand /><span className="topbar-label">ENTORNO DE DEMOSTRACIÓN</span></header><Login onLogin={setToken} /><footer className="login-footer"><span>© Zero Trust Lab · Proyecto académico</span><span><ShieldCheck size={14} /> La seguridad se aplica en el servidor</span></footer></>}</div>
}

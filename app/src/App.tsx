import { Navigate, Route, Routes, useParams } from 'react-router-dom'
import { AppShell } from './components/AppShell'
import { ToastProvider } from './hooks/useToast'
import { useQuery } from './hooks/useQuery'
import * as api from './lib/api'
import { Spinner } from './components/ui'

import Dashboard from './pages/Dashboard'
import NewProject from './pages/NewProject'
import Login from './pages/Login'
import Overview from './pages/project/Overview'
import Guide from './pages/project/Guide'
import Deadlines from './pages/project/Deadlines'
import Diary from './pages/project/Diary'
import HiddenWorks from './pages/project/HiddenWorks'
import Measurements from './pages/project/Measurements'
import Payments from './pages/project/Payments'
import ApePage from './pages/project/Ape'
import NewApe from './pages/project/NewApe'
import ApeDocuments from './pages/project/ApeDocuments'
import Budget from './pages/project/Budget'
import NewPayment from './pages/project/NewPayment'
import Guarantees from './pages/project/Guarantees'
import CompletionPage from './pages/project/Completion'
import Documents from './pages/project/Documents'

function Shell({ children }: { children: React.ReactNode }) {
  const { projectId } = useParams()
  const { data: org } = useQuery(() => api.getOrganization(), [])
  const { data: user } = useQuery(() => api.getProfile(), [])
  const { data: project } = useQuery(
    () => (projectId ? api.getProject(projectId) : Promise.resolve(undefined)),
    [projectId],
  )
  return (
    <AppShell org={org} user={user} projectTitle={project?.title} projectCode={project?.code}>
      {children}
    </AppShell>
  )
}

export default function App() {
  const { data: user, loading } = useQuery(() => api.getProfile().catch(() => null), [])

  if (loading) return <Spinner />
  if (!api.DEMO_MODE && !user) return <Login />

  return (
    <ToastProvider>
      <Routes>
        <Route path="/" element={<Shell><Dashboard /></Shell>} />
        <Route path="/neo-ergo" element={<Shell><NewProject /></Shell>} />
        <Route path="/erga/:projectId" element={<Shell><Overview /></Shell>} />
        <Route path="/erga/:projectId/odigos" element={<Shell><Guide /></Shell>} />
        <Route path="/erga/:projectId/prothesmies" element={<Shell><Deadlines /></Shell>} />
        <Route path="/erga/:projectId/imerologio" element={<Shell><Diary /></Shell>} />
        <Route path="/erga/:projectId/afaneis" element={<Shell><HiddenWorks /></Shell>} />
        <Route path="/erga/:projectId/epimetriseis" element={<Shell><Measurements /></Shell>} />
        <Route path="/erga/:projectId/logariasmoi" element={<Shell><Payments /></Shell>} />
        <Route path="/erga/:projectId/logariasmoi/neos" element={<Shell><NewPayment /></Shell>} />
        <Route path="/erga/:projectId/ape" element={<Shell><ApePage /></Shell>} />
        <Route path="/erga/:projectId/ape/neos" element={<Shell><NewApe /></Shell>} />
        <Route path="/erga/:projectId/ape/:apeId/eggrafa" element={<Shell><ApeDocuments /></Shell>} />
        <Route path="/erga/:projectId/proypologismos" element={<Shell><Budget /></Shell>} />
        <Route path="/erga/:projectId/eggyiseis" element={<Shell><Guarantees /></Shell>} />
        <Route path="/erga/:projectId/peraiosi" element={<Shell><CompletionPage /></Shell>} />
        <Route path="/erga/:projectId/eggrafa" element={<Shell><Documents /></Shell>} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </ToastProvider>
  )
}

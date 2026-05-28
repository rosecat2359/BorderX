import { Link, Outlet, useNavigate, useLocation } from 'react-router-dom'
import { useAuth } from '../../store/auth'

export default function AdminLayout() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()
  const location = useLocation()

  const handleLogout = () => {
    logout()
    navigate('/')
  }

  const linkClass = (path: string) =>
    `block px-4 py-2 rounded-lg transition-colors ${
      location.pathname === path || (path !== '/admin' && location.pathname.startsWith(path))
        ? 'bg-blue-600 text-white'
        : 'text-gray-300 hover:bg-gray-700 hover:text-white'
    }`

  return (
    <div className="min-h-screen flex">
      <aside className="w-60 bg-gray-900 flex flex-col shrink-0">
        <div className="p-6">
          <Link to="/admin" className="text-2xl font-bold text-white">BorderX</Link>
          <p className="text-gray-400 text-sm mt-1">管理后台</p>
        </div>

        <nav className="flex-1 px-4 space-y-1">
          <Link to="/admin" className={linkClass('/admin/dashboard') || linkClass('/admin')}>仪表盘</Link>
          <Link to="/admin/users" className={linkClass('/admin/users')}>用户管理</Link>
          <Link to="/admin/traffic" className={linkClass('/admin/traffic')}>流量统计</Link>
          <Link to="/admin/orders" className={linkClass('/admin/orders')}>订单管理</Link>
          <Link to="/admin/plans" className={linkClass('/admin/plans')}>套餐管理</Link>
        </nav>

        <div className="p-4 border-t border-gray-700">
          <div className="text-gray-300 text-sm mb-1">{user?.email}</div>
          <div className="text-gray-500 text-xs mb-3">{user?.role === 'admin' ? '管理员' : user?.role}</div>
          <button
            onClick={handleLogout}
            className="w-full px-4 py-2 text-gray-300 hover:text-white hover:bg-gray-700 rounded-lg text-sm transition-colors"
          >
            退出登录
          </button>
        </div>
      </aside>

      <main className="flex-1 bg-gray-50 p-8 overflow-auto">
        <Outlet />
      </main>
    </div>
  )
}

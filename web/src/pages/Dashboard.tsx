import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../store/auth'

export default function Dashboard() {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = () => {
    logout()
    navigate('/')
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <Link to="/" className="text-2xl font-bold text-blue-600">BorderX</Link>
          <div className="flex items-center gap-4">
            <span className="text-gray-600">{user?.email}</span>
            <button
              onClick={handleLogout}
              className="px-4 py-2 text-gray-700 hover:text-red-600 font-medium transition-colors"
            >
              退出
            </button>
          </div>
        </div>
      </nav>

      <main className="max-w-7xl mx-auto px-4 py-12">
        <h1 className="text-3xl font-bold text-gray-900 mb-8">我的仪表盘</h1>

        <div className="grid grid-cols-1 md:grid-cols-2 gap-8">
          <div className="bg-white rounded-2xl shadow-md p-8 border border-gray-100">
            <h2 className="text-xl font-bold text-gray-900 mb-4">VPN 账号</h2>
            <p className="text-gray-500">
              购买套餐后，VPN 账号将自动创建。请先选购套餐以开始使用服务。
            </p>
          </div>

          <div className="bg-white rounded-2xl shadow-md p-8 border border-gray-100">
            <h2 className="text-xl font-bold text-gray-900 mb-4">我的订单</h2>
            <p className="text-gray-500">
              暂无订单记录。
            </p>
          </div>
        </div>
      </main>
    </div>
  )
}

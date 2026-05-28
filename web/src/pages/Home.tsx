import { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import { plans } from '../api'
import type { Plan } from '../api'

export default function Home() {
  const [planList, setPlanList] = useState<Plan[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    plans.list()
      .then((res) => setPlanList(res.data))
      .catch(() => {})
      .finally(() => setLoading(false))
  }, [])

  return (
    <div className="min-h-screen bg-gray-50">
      <nav className="bg-white shadow-sm">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 h-16 flex items-center justify-between">
          <Link to="/" className="text-2xl font-bold text-blue-600">BorderX</Link>
          <div className="flex gap-4">
            <Link to="/login" className="px-4 py-2 text-gray-700 hover:text-blue-600 font-medium">登录</Link>
            <Link to="/register" className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium">注册</Link>
          </div>
        </div>
      </nav>

      <header className="bg-gradient-to-r from-blue-600 to-indigo-700 text-white py-20">
        <div className="max-w-7xl mx-auto px-4 text-center">
          <h1 className="text-5xl font-bold mb-4">安全 · 高速 · 全球节点</h1>
          <p className="text-xl text-blue-100">全球覆盖，极速体验，守护您的每一次连接</p>
        </div>
      </header>

      <section className="max-w-7xl mx-auto px-4 py-16">
        <h2 className="text-3xl font-bold text-center mb-12">选择适合您的套餐</h2>
        {loading ? (
          <div className="text-center text-gray-500 py-12">加载中...</div>
        ) : planList.length === 0 ? (
          <div className="text-center text-gray-500 py-12">暂无可用套餐</div>
        ) : (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
            {planList.map((plan) => (
              <div key={plan.id} className="bg-white rounded-2xl shadow-md hover:shadow-xl transition-shadow p-8 border border-gray-100">
                <h3 className="text-2xl font-bold text-gray-900 mb-2">{plan.name}</h3>
                <div className="text-4xl font-bold text-blue-600 mb-4">
                  ¥{(plan.price_cents / 100).toFixed(2)}
                  <span className="text-lg font-normal text-gray-400">/{plan.duration_days === 30 ? '月' : plan.duration_days === 365 ? '年' : `${plan.duration_days}天`}</span>
                </div>
                <ul className="space-y-3 mb-8 text-gray-600">
                  <li className="flex items-center gap-2">
                    <span className="text-green-500">&#10003;</span>
                    {plan.traffic_limit_gb}GB 流量
                  </li>
                  <li className="flex items-center gap-2">
                    <span className="text-green-500">&#10003;</span>
                    最长 {plan.duration_days} 天
                  </li>
                  <li className="flex items-center gap-2">
                    <span className="text-green-500">&#10003;</span>
                    支持 {plan.max_devices} 台设备
                  </li>
                </ul>
                <Link
                  to="/register"
                  className="block w-full text-center py-3 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
                >
                  立即购买
                </Link>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  )
}

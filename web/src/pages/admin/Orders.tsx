import { useState, useEffect } from 'react'
import { admin } from '../../api'

interface Order {
  id: string
  plan_name: string
  amount_cents: number
  status: string
  created_at: string
}

const statusLabels: Record<string, string> = {
  pending: '待支付',
  paid: '已支付',
  cancelled: '已取消',
}

const statusColors: Record<string, string> = {
  pending: 'bg-yellow-100 text-yellow-700',
  paid: 'bg-green-100 text-green-700',
  cancelled: 'bg-gray-100 text-gray-500',
}

export default function AdminOrders() {
  const [orders, setOrders] = useState<Order[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')

  const fetchOrders = () => {
    setLoading(true)
    setError('')
    admin.listOrders()
      .then((res) => setOrders(res.data))
      .catch((err) => setError(err.response?.data?.error || '加载失败'))
      .finally(() => setLoading(false))
  }

  useEffect(() => { fetchOrders() }, [])

  const handleCancel = async (id: string) => {
    if (!confirm('确定要取消该订单吗？')) return
    try {
      await admin.cancelOrder(id)
      fetchOrders()
    } catch (err: any) {
      setError(err.response?.data?.error || '操作失败')
    }
  }

  return (
    <div>
      <h1 className="text-3xl font-bold text-gray-900 mb-8">订单管理</h1>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-sm">{error}</div>
      )}

      {loading ? (
        <div className="text-center text-gray-500 py-12">加载中...</div>
      ) : (
        <div className="bg-white rounded-2xl shadow-md border border-gray-100 overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50">
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">ID</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">套餐</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">金额</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">状态</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">创建时间</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">操作</th>
              </tr>
            </thead>
            <tbody>
              {orders.length === 0 ? (
                <tr>
                  <td colSpan={6} className="text-center text-gray-500 py-12">暂无数据</td>
                </tr>
              ) : (
                orders.map((o) => (
                  <tr key={o.id} className="border-b border-gray-100">
                    <td className="px-6 py-4 text-gray-500 text-sm font-mono">
                      {o.id.substring(0, 8)}
                    </td>
                    <td className="px-6 py-4 text-gray-900">{o.plan_name}</td>
                    <td className="px-6 py-4 text-gray-900">
                      ¥{(o.amount_cents / 100).toFixed(2)}
                    </td>
                    <td className="px-6 py-4">
                      <span className={`inline-block px-2 py-1 rounded-full text-xs font-medium ${statusColors[o.status] || 'bg-gray-100 text-gray-500'}`}>
                        {statusLabels[o.status] || o.status}
                      </span>
                    </td>
                    <td className="px-6 py-4 text-gray-500 text-sm">
                      {new Date(o.created_at).toLocaleDateString('zh-CN')}
                    </td>
                    <td className="px-6 py-4">
                      {o.status === 'pending' && (
                        <button
                          onClick={() => handleCancel(o.id)}
                          className="px-3 py-1 bg-red-100 text-red-700 rounded-lg text-sm hover:bg-red-200 transition-colors"
                        >
                          取消
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      )}
    </div>
  )
}

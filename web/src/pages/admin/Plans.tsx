import { useState, useEffect } from 'react'
import { admin } from '../../api'
import type { Plan } from '../../api'

const emptyPlan = {
  name: '',
  price_cents: 0,
  duration_days: 30,
  traffic_limit_gb: 100,
  max_devices: 3,
  is_active: true,
}

export default function AdminPlans() {
  const [plans, setPlans] = useState<Plan[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [showForm, setShowForm] = useState(false)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [form, setForm] = useState({ ...emptyPlan, sort_order: 0 })

  const fetchPlans = () => {
    setLoading(true)
    setError('')
    admin.listPlans()
      .then((res) => setPlans(res.data))
      .catch((err) => setError(err.response?.data?.error || '加载失败'))
      .finally(() => setLoading(false))
  }

  useEffect(() => { fetchPlans() }, [])

  const openCreate = () => {
    setEditingId(null)
    setForm({ ...emptyPlan, sort_order: 0 })
    setShowForm(true)
  }

  const openEdit = (plan: Plan & { sort_order?: number }) => {
    setEditingId(plan.id)
    setForm({
      name: plan.name,
      price_cents: plan.price_cents,
      duration_days: plan.duration_days,
      traffic_limit_gb: plan.traffic_limit_gb,
      max_devices: plan.max_devices,
      is_active: plan.is_active,
      sort_order: (plan as any).sort_order ?? 0,
    })
    setShowForm(true)
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError('')
    try {
      if (editingId) {
        await admin.updatePlan(editingId, form)
      } else {
        await admin.createPlan(form)
      }
      setShowForm(false)
      fetchPlans()
    } catch (err: any) {
      setError(err.response?.data?.error || '保存失败')
    }
  }

  const handleDelete = async (id: string) => {
    if (!confirm('确定要删除该套餐吗？')) return
    try {
      await admin.deletePlan(id)
      fetchPlans()
    } catch (err: any) {
      setError(err.response?.data?.error || '删除失败')
    }
  }

  const updateField = (field: string, value: string | number | boolean) => {
    setForm((prev) => ({ ...prev, [field]: value }))
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold text-gray-900">套餐管理</h1>
        <button
          onClick={openCreate}
          className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
        >
          新增套餐
        </button>
      </div>

      {error && (
        <div className="mb-4 p-3 bg-red-50 border border-red-200 text-red-700 rounded-lg text-sm">{error}</div>
      )}

      {showForm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50">
          <div className="bg-white rounded-2xl shadow-xl p-8 w-full max-w-lg mx-4">
            <h2 className="text-xl font-bold text-gray-900 mb-6">
              {editingId ? '编辑套餐' : '新增套餐'}
            </h2>
            <form onSubmit={handleSubmit} className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-1">名称</label>
                <input
                  type="text"
                  value={form.name}
                  onChange={(e) => updateField('name', e.target.value)}
                  required
                  className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                />
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">价格（分）</label>
                  <input
                    type="number"
                    value={form.price_cents}
                    onChange={(e) => updateField('price_cents', parseInt(e.target.value) || 0)}
                    required
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">天数</label>
                  <input
                    type="number"
                    value={form.duration_days}
                    onChange={(e) => updateField('duration_days', parseInt(e.target.value) || 0)}
                    required
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">流量 (GB)</label>
                  <input
                    type="number"
                    value={form.traffic_limit_gb}
                    onChange={(e) => updateField('traffic_limit_gb', parseInt(e.target.value) || 0)}
                    required
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">设备数</label>
                  <input
                    type="number"
                    value={form.max_devices}
                    onChange={(e) => updateField('max_devices', parseInt(e.target.value) || 0)}
                    required
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-gray-700 mb-1">排序</label>
                  <input
                    type="number"
                    value={form.sort_order}
                    onChange={(e) => updateField('sort_order', parseInt(e.target.value) || 0)}
                    className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500 outline-none"
                  />
                </div>
                <div className="flex items-end">
                  <label className="flex items-center gap-2 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={form.is_active}
                      onChange={(e) => updateField('is_active', e.target.checked)}
                      className="w-4 h-4 text-blue-600 rounded focus:ring-blue-500"
                    />
                    <span className="text-sm font-medium text-gray-700">启用</span>
                  </label>
                </div>
              </div>
              <div className="flex gap-3 justify-end pt-4">
                <button
                  type="button"
                  onClick={() => setShowForm(false)}
                  className="px-6 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 font-medium transition-colors"
                >
                  取消
                </button>
                <button
                  type="submit"
                  className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
                >
                  保存
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {loading ? (
        <div className="text-center text-gray-500 py-12">加载中...</div>
      ) : (
        <div className="bg-white rounded-2xl shadow-md border border-gray-100 overflow-hidden">
          <table className="w-full">
            <thead>
              <tr className="border-b border-gray-200 bg-gray-50">
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">名称</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">价格</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">天数</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">流量</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">状态</th>
                <th className="text-left px-6 py-4 text-sm font-medium text-gray-500">操作</th>
              </tr>
            </thead>
            <tbody>
              {plans.length === 0 ? (
                <tr>
                  <td colSpan={6} className="text-center text-gray-500 py-12">暂无数据</td>
                </tr>
              ) : (
                plans.map((p) => (
                  <tr key={p.id} className="border-b border-gray-100">
                    <td className="px-6 py-4 text-gray-900 font-medium">{p.name}</td>
                    <td className="px-6 py-4 text-gray-900">¥{(p.price_cents / 100).toFixed(2)}</td>
                    <td className="px-6 py-4 text-gray-500">{p.duration_days} 天</td>
                    <td className="px-6 py-4 text-gray-500">{p.traffic_limit_gb} GB</td>
                    <td className="px-6 py-4">
                      <span className={`inline-block px-2 py-1 rounded-full text-xs font-medium ${
                        p.is_active ? 'bg-green-100 text-green-700' : 'bg-gray-100 text-gray-500'
                      }`}>
                        {p.is_active ? '启用' : '禁用'}
                      </span>
                    </td>
                    <td className="px-6 py-4">
                      <div className="flex gap-2">
                        <button
                          onClick={() => openEdit(p)}
                          className="px-3 py-1 bg-blue-100 text-blue-700 rounded-lg text-sm hover:bg-blue-200 transition-colors"
                        >
                          编辑
                        </button>
                        <button
                          onClick={() => handleDelete(p.id)}
                          className="px-3 py-1 bg-red-100 text-red-700 rounded-lg text-sm hover:bg-red-200 transition-colors"
                        >
                          删除
                        </button>
                      </div>
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

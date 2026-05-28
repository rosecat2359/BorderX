import { useState, useEffect } from 'react'
import { admin } from '../../api'

const ACTION_LABELS: Record<string, string> = {
  'user.disable': '禁用用户',
  'user.enable': '启用用户',
  'plan.create': '创建套餐',
  'plan.update': '更新套餐',
  'plan.delete': '删除套餐',
  'order.cancel': '取消订单',
}

export default function AdminAudit() {
  const [logs, setLogs] = useState<any[]>([])
  const [total, setTotal] = useState(0)
  const [page, setPage] = useState(1)

  useEffect(() => {
    admin.getAuditLogs(page).then(({ data }) => {
      setLogs(data.items || [])
      setTotal(data.total)
    })
  }, [page])

  return (
    <div>
      <h2 className="text-2xl font-bold mb-4">操作日志</h2>
      <table className="w-full bg-white shadow rounded">
        <thead><tr className="text-left border-b"><th className="p-3">时间</th><th className="p-3">管理员</th><th className="p-3">操作</th><th className="p-3">目标类型</th><th className="p-3">目标ID</th></tr></thead>
        <tbody>
          {logs.map((l: any) => (
            <tr key={l.id} className="border-b">
              <td className="p-3 text-sm text-gray-600">{new Date(l.created_at).toLocaleString()}</td>
              <td className="p-3">{l.admin_name}</td>
              <td className="p-3">{ACTION_LABELS[l.action] || l.action}</td>
              <td className="p-3">{l.target_type}</td>
              <td className="p-3 text-gray-400 text-sm">{l.target_id?.substring(0, 8)}...</td>
            </tr>
          ))}
        </tbody>
      </table>
      {total > 20 && (
        <div className="mt-4 flex justify-center gap-2">
          <button disabled={page <= 1} onClick={() => setPage(page - 1)} className="px-3 py-1 border rounded disabled:opacity-30">上一页</button>
          <span className="px-3 py-1">第 {page} 页</span>
          <button disabled={page >= Math.ceil(total / 20)} onClick={() => setPage(page + 1)} className="px-3 py-1 border rounded disabled:opacity-30">下一页</button>
        </div>
      )}
    </div>
  )
}

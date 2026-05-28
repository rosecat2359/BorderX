import { useState, useEffect } from 'react'
import { admin } from '../../api'

export default function AdminTraffic() {
  const [summary, setSummary] = useState<any>({})
  const [accounts, setAccounts] = useState<any[]>([])
  const [timeline, setTimeline] = useState<any[]>([])
  const [days, setDays] = useState(7)

  useEffect(() => {
    admin.getTrafficSummary().then(({ data }) => setSummary(data))
    admin.getTrafficAccounts(days).then(({ data }) => setAccounts(data))
    admin.getTrafficTimeline().then(({ data }) => setTimeline(data))
  }, [days])

  return (
    <div>
      <h2 className="text-2xl font-bold mb-6">流量统计</h2>

      {/* Summary Cards */}
      <div className="grid grid-cols-3 gap-6 mb-8">
        <div className="bg-white p-6 rounded-lg shadow">
          <p className="text-gray-500 text-sm">30天上行</p>
          <p className="text-3xl font-bold">{summary.total_upload_gb?.toFixed(1) ?? '0'} GB</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <p className="text-gray-500 text-sm">30天下行</p>
          <p className="text-3xl font-bold">{summary.total_download_gb?.toFixed(1) ?? '0'} GB</p>
        </div>
        <div className="bg-white p-6 rounded-lg shadow">
          <p className="text-gray-500 text-sm">活跃账号</p>
          <p className="text-3xl font-bold">{summary.active_accounts ?? '0'}</p>
        </div>
      </div>

      {/* Per-Account Table */}
      <div className="bg-white rounded-lg shadow mb-8">
        <div className="p-4 border-b flex justify-between items-center">
          <h3 className="font-bold">账号流量排行</h3>
          <select value={days} onChange={(e) => setDays(+e.target.value)} className="border rounded px-2 py-1">
            <option value={1}>最近 1 天</option>
            <option value={7}>最近 7 天</option>
            <option value={30}>最近 30 天</option>
          </select>
        </div>
        <table className="w-full">
          <thead><tr className="text-left border-b"><th className="p-3">用户</th><th className="p-3">协议</th><th className="p-3">上行</th><th className="p-3">下行</th><th className="p-3">合计</th></tr></thead>
          <tbody>
            {accounts.map((a: any, i: number) => (
              <tr key={i} className="border-b">
                <td className="p-3">{a.email}</td>
                <td className="p-3"><span className="px-2 py-1 bg-blue-100 text-blue-700 rounded text-xs">{a.protocol}</span></td>
                <td className="p-3">{a.upload_gb?.toFixed(2)} GB</td>
                <td className="p-3">{a.download_gb?.toFixed(2)} GB</td>
                <td className="p-3 font-medium">{a.total_gb?.toFixed(2)} GB</td>
              </tr>
            ))}
            {accounts.length === 0 && <tr><td colSpan={5} className="p-6 text-center text-gray-400">暂无数据</td></tr>}
          </tbody>
        </table>
      </div>

      {/* Timeline */}
      <div className="bg-white rounded-lg shadow">
        <div className="p-4 border-b"><h3 className="font-bold">24小时流量趋势</h3></div>
        <div className="p-4 overflow-x-auto">
          {timeline.length > 0 ? (
            <div className="flex items-end gap-1 h-40">
              {timeline.map((t: any, i: number) => {
                const max = Math.max(...timeline.map((x: any) => x.upload_gb + x.download_gb), 0.01)
                const height = (t.upload_gb + t.download_gb) / max * 100
                return (
                  <div key={i} className="flex-1 relative group" title={`${t.hour}: ${(t.upload_gb+t.download_gb).toFixed(2)} GB`}>
                    <div className="bg-blue-500 rounded-t w-full absolute bottom-0" style={{ height: `${height}%`, minHeight: '2px' }}></div>
                  </div>
                )
              })}
            </div>
          ) : (
            <p className="text-center text-gray-400 py-8">暂无数据（需要 Xray 运行后才有流量记录）</p>
          )}
        </div>
      </div>
    </div>
  )
}

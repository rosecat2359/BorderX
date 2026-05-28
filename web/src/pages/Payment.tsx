import { useState, useEffect, useRef } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { orders } from '../api'

interface LocationState {
  orderId?: string
  qrCode?: string
  amount?: number
  planName?: string
}

export default function Payment() {
  const navigate = useNavigate()
  const location = useLocation()
  const state = (location.state as LocationState) || {}

  const [status, setStatus] = useState<string>('pending')
  const [error, setError] = useState('')
  const pollRef = useRef<ReturnType<typeof setInterval> | undefined>(undefined)

  const orderId = state.orderId
  const qrCode = state.qrCode
  const amount = state.amount
  const planName = state.planName

  // Poll order status every 3 seconds
  useEffect(() => {
    if (!orderId) {
      setError('缺少订单信息，请返回重新下单')
      return
    }

    const poll = () => {
      orders
        .status(orderId)
        .then((res) => {
          const s = res.data.status
          setStatus(s)
          if (s === 'paid') {
            clearInterval(pollRef.current)
            setTimeout(() => navigate('/dashboard', { replace: true }), 1500)
          }
        })
        .catch(() => {
          // Silently ignore poll errors; keep trying
        })
    }

    poll() // immediate first check
    pollRef.current = setInterval(poll, 3000)

    return () => clearInterval(pollRef.current)
  }, [orderId, navigate])

  // Build QR code image URL using a free QR code API
  const qrImageUrl = qrCode
    ? `https://api.qrserver.com/v1/create-qr-code/?size=260x260&data=${encodeURIComponent(qrCode)}`
    : ''

  return (
    <div className="min-h-screen bg-gray-50 flex flex-col items-center justify-center px-4">
      <div className="bg-white rounded-2xl shadow-lg p-8 max-w-md w-full text-center border border-gray-100">
        {error ? (
          <>
            <div className="text-red-500 text-lg mb-4">{error}</div>
            <button
              onClick={() => navigate('/')}
              className="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium transition-colors"
            >
              返回首页
            </button>
          </>
        ) : status === 'paid' ? (
          <>
            <div className="text-green-500 text-6xl mb-4">&#10003;</div>
            <h2 className="text-2xl font-bold text-gray-900 mb-2">支付成功</h2>
            <p className="text-gray-500 mb-4">正在跳转到仪表盘...</p>
          </>
        ) : (
          <>
            <h1 className="text-2xl font-bold text-gray-900 mb-2">扫码支付</h1>
            {planName && (
              <p className="text-gray-600 mb-1">
                {planName}
                {amount !== undefined && (
                  <span className="text-blue-600 font-bold ml-1">
                    ¥{amount.toFixed(2)}
                  </span>
                )}
              </p>
            )}
            <p className="text-sm text-gray-400 mb-6">请使用支付宝扫描二维码完成支付</p>

            {qrImageUrl ? (
              <div className="bg-gray-50 rounded-xl p-4 inline-block mb-6 border border-gray-200">
                <img
                  src={qrImageUrl}
                  alt="支付宝收款码"
                  width={260}
                  height={260}
                  className="rounded-lg"
                />
              </div>
            ) : (
              <div className="bg-yellow-50 border border-yellow-200 rounded-xl p-4 mb-6 text-yellow-700 text-sm">
                未能生成支付二维码，请稍后重试或联系客服。
              </div>
            )}

            <div className="flex items-center justify-center gap-2 text-gray-400 text-sm">
              <svg className="animate-spin h-4 w-4" viewBox="0 0 24 24">
                <circle
                  className="opacity-25"
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="currentColor"
                  strokeWidth="4"
                  fill="none"
                />
                <path
                  className="opacity-75"
                  fill="currentColor"
                  d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"
                />
              </svg>
              等待支付中...
            </div>

            {orderId && (
              <p className="mt-4 text-xs text-gray-400 break-all">
                订单号: {orderId}
              </p>
            )}
          </>
        )}
      </div>
    </div>
  )
}

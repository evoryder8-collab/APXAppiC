/*
 * Slowly drifting ambient gradient blobs behind the whole app,
 * plus a fine grain overlay. This is what the frosted glass melts into.
 */
export function AmbientBackground() {
  return (
    <>
      <div className="fixed inset-0 -z-10 overflow-hidden" aria-hidden>
        <div
          className="blob"
          style={{
            width: '58vmax',
            height: '58vmax',
            top: '-18vmax',
            right: '-12vmax',
            background:
              'radial-gradient(circle at 40% 40%, rgba(251, 191, 36, 0.5) 0%, rgba(251, 191, 36, 0) 68%)',
            animation: 'drift-1 84s ease-in-out infinite',
          }}
        />
        <div
          className="blob"
          style={{
            width: '52vmax',
            height: '52vmax',
            top: '22vh',
            left: '-16vmax',
            background:
              'radial-gradient(circle at 55% 45%, rgba(45, 212, 191, 0.48) 0%, rgba(45, 212, 191, 0) 68%)',
            animation: 'drift-2 102s ease-in-out infinite',
          }}
        />
        <div
          className="blob"
          style={{
            width: '48vmax',
            height: '48vmax',
            top: '-14vmax',
            left: '-10vmax',
            background:
              'radial-gradient(circle at 45% 45%, rgba(167, 139, 250, 0.46) 0%, rgba(167, 139, 250, 0) 68%)',
            animation: 'drift-3 118s ease-in-out infinite',
          }}
        />
        <div
          className="blob"
          style={{
            width: '46vmax',
            height: '46vmax',
            bottom: '-14vmax',
            right: '-8vmax',
            background:
              'radial-gradient(circle at 50% 50%, rgba(52, 211, 153, 0.4) 0%, rgba(52, 211, 153, 0) 68%)',
            animation: 'drift-2 96s ease-in-out infinite reverse',
          }}
        />
        <div
          className="blob"
          style={{
            width: '44vmax',
            height: '44vmax',
            bottom: '-10vmax',
            left: '-8vmax',
            background:
              'radial-gradient(circle at 50% 50%, rgba(125, 211, 252, 0.42) 0%, rgba(125, 211, 252, 0) 68%)',
            animation: 'drift-1 110s ease-in-out infinite reverse',
          }}
        />
      </div>
      <div className="grain" aria-hidden />
    </>
  )
}

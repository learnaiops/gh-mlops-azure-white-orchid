export default function Header() {
  return (
    <header className="header">
      <div className="header-inner">
        <a href="/" className="logo">
          <div className="logo-mark">WO</div>
          <div>
            <span className="logo-text">White Orchid</span>
            <span className="logo-sub">AI Risk Intelligence</span>
          </div>
        </a>
        <div className="header-right">
          <span className="header-badge">AI-Powered</span>
          <span className="header-env">Pre-Prod · Azure ML</span>
        </div>
      </div>
    </header>
  );
}

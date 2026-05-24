export default function Header() {
  return (
    <header className="header">
      <div className="header-inner">
        <a href="/" className="logo">
          <div className="logo-mark">WO</div>
          <div>
            <span className="logo-text">White Orchid</span>
            <span className="logo-sub">Health Insurance Risk</span>
          </div>
        </a>
        <span className="header-badge">Azure ML · Pre-Prod</span>
      </div>
    </header>
  );
}

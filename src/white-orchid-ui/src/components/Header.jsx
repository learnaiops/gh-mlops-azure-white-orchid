export default function Header() {
  return (
    <header className="header">
      <div className="header-inner">
        <a href="/" className="logo">
          <img
            src="https://img.crocdn.co.uk/lib/images/products/pl/00/00/00/66/pl0000006610.jpg?width=940&height=940"
            alt="White Orchid"
            className="logo-orchid"
          />
          <div>
            <span className="logo-text">White Orchid</span>
            <span className="logo-sub">AI Risk Intelligence</span>
          </div>
        </a>
        <div className="header-right">
          <span className="header-badge">AI-Powered</span>
          <span className="header-env">Azure ML · Pre-Prod + Prod</span>
        </div>
      </div>
    </header>
  );
}

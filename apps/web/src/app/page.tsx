export default function Home() {
  return (
    <main className="shell">
      <form className="lookup">
        <h1 className="brand">wat</h1>
        <input
          aria-label="Search"
          autoFocus
          className="search"
          name="q"
          placeholder="API, CAP, TLS"
          type="search"
        />
      </form>
    </main>
  );
}

import { useCallback, useEffect, useRef, useState } from "react";

const fmtSize = (n) =>
  n < 1024 ? `${n} B` : n < 1048576 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1048576).toFixed(1)} MB`;

export default function App() {
  const [files, setFiles] = useState([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [pods, setPods] = useState([]); // which API pods answered the last health checks
  const [ready, setReady] = useState(null);
  const input = useRef(null);

  const load = useCallback(async () => {
    try {
      const r = await fetch("/api/files");
      if (!r.ok) throw new Error(`list failed (${r.status})`);
      setFiles(await r.json());
      setError("");
    } catch (e) {
      setError(e.message);
    }
  }, []);

  // Poll health every 2 s: shows which pod served each request (load balancing / failover in action).
  useEffect(() => {
    load();
    const t = setInterval(async () => {
      try {
        const [h, rd] = await Promise.all([fetch("/api/healthz"), fetch("/api/readyz")]);
        const { pod } = await h.json();
        setPods((p) => [pod, ...p].slice(0, 8));
        setReady(rd.ok);
      } catch {
        setReady(false);
      }
    }, 2000);
    return () => clearInterval(t);
  }, [load]);

  const upload = async (e) => {
    e.preventDefault();
    const f = input.current.files[0];
    if (!f) return;
    setBusy(true);
    const body = new FormData();
    body.append("file", f);
    const r = await fetch("/api/files", { method: "POST", body });
    setBusy(false);
    if (!r.ok) return setError(`upload failed (${r.status})`);
    input.current.value = "";
    load();
  };

  const remove = async (id) => {
    const r = await fetch(`/api/files/${id}`, { method: "DELETE" });
    if (!r.ok) return setError(`delete failed (${r.status})`);
    load();
  };

  return (
    <main>
      <header>
        <h1>HA Storage</h1>
        <p className="sub">Files replicated on 3 GlusterFS nodes · API on Kubernetes</p>
        <span className={`badge ${ready ? "ok" : ready === false ? "bad" : ""}`}>
          {ready === null ? "checking…" : ready ? "ready" : "degraded"}
        </span>
      </header>

      <section className="card">
        <form onSubmit={upload}>
          <input type="file" ref={input} aria-label="File to upload" />
          <button disabled={busy}>{busy ? "Uploading…" : "Upload"}</button>
        </form>
        {error && <p className="error">{error}</p>}
      </section>

      <section className="card">
        <h2>Files ({files.length})</h2>
        {files.length === 0 ? (
          <p className="muted">No files yet.</p>
        ) : (
          <table>
            <thead>
              <tr><th>Name</th><th>Size</th><th>SHA-256</th><th>Uploaded</th><th></th></tr>
            </thead>
            <tbody>
              {files.map((f) => (
                <tr key={f.id}>
                  <td>{f.name}</td>
                  <td>{fmtSize(f.size_bytes)}</td>
                  <td className="mono" title={f.sha256}>{f.sha256.slice(0, 12)}…</td>
                  <td>{new Date(f.created_at).toLocaleString()}</td>
                  <td className="actions">
                    <a href={`/api/files/${f.id}`}>Download</a>
                    <button className="link" onClick={() => remove(f.id)}>Delete</button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </section>

      <section className="card">
        <h2>Served by</h2>
        <p className="muted">Latest health checks, newest first: each line is the API pod that answered.</p>
        <ul className="pods">{pods.map((p, i) => <li key={i} className="mono">{p}</li>)}</ul>
      </section>
    </main>
  );
}

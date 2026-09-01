"use client";

import { FormEvent, useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [passwordConfirmation, setPasswordConfirmation] = useState("");
  const [fullName, setFullName] = useState("");
  const [isSignUp, setIsSignUp] = useState(false);
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setMessage("");
    if (isSignUp && password !== passwordConfirmation) {
      setMessage("Las contraseñas no coinciden.");
      setBusy(false);
      return;
    }
    const result = isSignUp
      ? await supabase.auth.signUp({ email, password, options: { data: { full_name: fullName } } })
      : await supabase.auth.signInWithPassword({ email, password });

    if (result.error) {
      const messages: Record<string, string> = {
        "Invalid login credentials": "El correo o la contraseña no son correctos.",
        "User already registered": "Ya existe una cuenta con ese correo.",
        "Password should be at least 6 characters.": "La contraseña debe tener al menos 8 caracteres.",
      };
      setMessage(messages[result.error.message] ?? result.error.message);
    } else if (isSignUp && !result.data.session) {
      setMessage("Revisa tu correo para confirmar la cuenta antes de entrar.");
    } else {
      router.replace("/");
      router.refresh();
    }
    setBusy(false);
  }

  return <main className="loginPage">
    <section className="loginCard">
      <div className="brandMark">CEI</div>
      <p className="eyebrow">CENTRO EDUCATIVO ITZAMNÁ</p>
      <h1>{isSignUp ? "Crear cuenta" : "Iniciar sesión"}</h1>
      <p className="loginIntro">Accede al control escolar y financiero.</p>
      <form onSubmit={submit}>
        {isSignUp && <label>Nombre completo<input required value={fullName} onChange={(event) => setFullName(event.target.value)} /></label>}
        <label>Correo electrónico<input required type="email" value={email} onChange={(event) => setEmail(event.target.value)} /></label>
        <label>Contraseña<input required minLength={8} type="password" autoComplete={isSignUp ? "new-password" : "current-password"} value={password} onChange={(event) => setPassword(event.target.value)} /></label>
        {isSignUp && <label>Confirmar contraseña<input required minLength={8} type="password" autoComplete="new-password" value={passwordConfirmation} onChange={(event) => setPasswordConfirmation(event.target.value)} /></label>}
        {message && <p className="formError">{message}</p>}
        <button className="primary loginSubmit" disabled={busy}>{busy ? "Procesando…" : isSignUp ? "Crear cuenta" : "Entrar"}</button>
      </form>
      <button className="loginSwitch" onClick={() => { setIsSignUp(!isSignUp); setMessage(""); setPasswordConfirmation(""); }}>
        {isSignUp ? "Ya tengo una cuenta" : "Crear la primera cuenta"}
      </button>
    </section>
  </main>;
}

import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { GolSwap } from "./GolSwap.tsx";
import "@fontsource-variable/inter";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <GolSwap />
  </StrictMode>,
);

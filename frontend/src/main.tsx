import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { GolSwap } from "./GolSwap.tsx";
import "./index.css";

createRoot(document.getElementById("root")!).render(
  <StrictMode>
    <GolSwap />
  </StrictMode>
);

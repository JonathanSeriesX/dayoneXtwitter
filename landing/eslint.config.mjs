import { fixupConfigRules } from "@eslint/compat";
import { defineConfig } from "eslint/config";
import coreWebVitals from "eslint-config-next/core-web-vitals";
import typescript from "eslint-config-next/typescript";

/* fixupConfigRules polyfills context.getFilename & co. for eslint-plugin-react,
   which eslint-config-next still ships and ESLint 10 broke. Drop it once
   eslint-plugin-react >7.37.5 (or an eslint-config-next without it) is out. */
export default defineConfig([
  { ignores: [".next/**", "out/**", "node_modules/**", "public/**"] },
  fixupConfigRules(coreWebVitals),
  fixupConfigRules(typescript),
]);

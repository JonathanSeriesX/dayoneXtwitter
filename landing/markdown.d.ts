/* What tools/raw-loader.cjs makes of an imported .md file. */
declare module "*.md" {
  const source: string;
  export default source;
}

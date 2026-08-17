/* Turns any file into `export default "<its text>"`. Wired to *.md in
   next.config.ts so content/page.md is a module the bundler watches — which is
   what makes an edit to the copy hot-reload instead of waiting for a restart. */
module.exports = function rawLoader(source) {
  return `export default ${JSON.stringify(source)};`;
};

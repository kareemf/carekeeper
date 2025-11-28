/* Initialize Mermaid once the page is ready.
 * mkdocs-material loads extra_javascript at the end of <body>, so we can safely start here.
 */
if (window.mermaid) {
  window.mermaid.initialize({
    startOnLoad: true,
    theme: 'default',
    securityLevel: 'strict',
  });
}

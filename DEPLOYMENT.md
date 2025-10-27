# Documentation Deployment Guide

This guide covers deploying the CareKeeper documentation site using Cloudflare Pages (recommended) or other hosting providers.

## Quick Start

### Local Preview

```bash
# Install dependencies (first time only)
pip3 install -r requirements.txt

# Serve locally with live reload
./scripts/serve-docs.sh

# Visit http://localhost:8000
```

### Build for Production

```bash
# Build static site
./scripts/build-docs.sh

# Output in site/ directory
```

## Cloudflare Pages (Recommended)

Cloudflare Pages is recommended because it:
- ✅ Works with private GitHub repos
- ✅ Free tier (unlimited bandwidth, builds)
- ✅ Automatic HTTPS
- ✅ Fast global CDN
- ✅ Git integration (auto-deploy on push)
- ✅ Preview deployments for PRs

### Initial Setup

1. **Push to GitHub** (if not already pushed)
   ```bash
   git push origin documentation
   ```

2. **Create Cloudflare Account**
   - Visit [dash.cloudflare.com](https://dash.cloudflare.com)
   - Sign up (free tier is sufficient)

3. **Create New Pages Project**
   - Go to Pages > Create a project
   - Connect to GitHub
   - Authorize Cloudflare to access your repo
   - Select the CareKeeper repository

4. **Configure Build Settings**
   ```
   Project name: carekeeper-docs
   Production branch: main (or documentation)
   Build command: pip install -r requirements.txt && mkdocs build
   Build output directory: site
   Root directory: (leave empty)
   ```

5. **Environment Variables** (none required for basic setup)

6. **Deploy**
   - Click "Save and Deploy"
   - Wait 2-3 minutes for first build
   - Site will be live at: `carekeeper-docs.pages.dev`

### Custom Domain (Optional)

To use your own domain (e.g., docs.carekeeper.com):

1. **Add Custom Domain in Cloudflare Pages**
   - Pages > Your project > Custom domains
   - Click "Set up a custom domain"
   - Enter your domain (e.g., docs.carekeeper.com)

2. **Update DNS**
   - Add CNAME record pointing to `carekeeper-docs.pages.dev`
   - Or use Cloudflare nameservers for automatic configuration

3. **SSL Certificate**
   - Automatic via Cloudflare (free)
   - HTTPS enforced by default

### Automatic Deployments

Once set up, deployments are automatic:
- **Push to production branch** → Deploys to production
- **Open pull request** → Creates preview deployment
- **Close pull request** → Deletes preview

### Private Repository Notes

Cloudflare Pages works with **private repos**, but:
- ✅ Documentation site is public (site is accessible)
- ✅ Source code remains private (repo not exposed)
- ✅ No special configuration needed

This allows you to:
- Keep CareKeeper code private during development
- Make documentation publicly accessible
- Open-source later without changing deployment

---

## Alternative Hosting Providers

### GitHub Pages

**Pros:**
- Free
- Integrated with GitHub
- Automatic HTTPS

**Cons:**
- Only works with **public** repos (or GitHub Pro)
- Slower than Cloudflare CDN
- More complex custom domain setup

**Setup:**
```bash
# Install ghp-import
pip install ghp-import

# Build and deploy
mkdocs gh-deploy --force

# Visit https://yourusername.github.io/carekeeper/
```

### Netlify

**Pros:**
- Works with private repos
- Free tier
- Good GitHub integration

**Cons:**
- Lower free tier bandwidth than Cloudflare
- Fewer edge locations

**Setup:**
1. Connect GitHub repo to Netlify
2. Build command: `pip install -r requirements.txt && mkdocs build`
3. Publish directory: `site`

### Vercel

**Pros:**
- Works with private repos
- Fast CDN
- Good developer experience

**Cons:**
- Smaller free tier
- Primarily for Next.js (works with static sites but not optimized)

**Setup:**
1. Connect GitHub repo to Vercel
2. Build command: `pip install -r requirements.txt && mkdocs build`
3. Output directory: `site`

### Self-Hosted (nginx)

For full control, host on your own server:

```bash
# Build site
./scripts/build-docs.sh

# Copy to server
rsync -avz site/ user@yourserver.com:/var/www/carekeeper-docs/

# Nginx config
server {
    listen 80;
    server_name docs.carekeeper.com;
    root /var/www/carekeeper-docs;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

---

## Updating Documentation

### Content Updates

1. **Edit markdown files** in `docs/`
2. **Preview locally**: `./scripts/serve-docs.sh`
3. **Commit and push**:
   ```bash
   git add docs/
   git commit -m "docs: Update [topic]"
   git push origin documentation
   ```
4. **Cloudflare auto-deploys** in 2-3 minutes

### Configuration Updates

To change theme, navigation, or other settings:

1. **Edit `mkdocs.yml`**
2. **Test locally**: `./scripts/serve-docs.sh`
3. **Commit and push**:
   ```bash
   git add mkdocs.yml
   git commit -m "docs: Update site configuration"
   git push origin documentation
   ```

---

## Adding Screenshots

Documentation includes `[SCREENSHOT: ...]` placeholders. To replace with real images:

1. **Capture screenshots** (use `scripts/capture-screenshots.sh` helper)
2. **Save images** to `docs/images/`
3. **Update markdown**:
   ```markdown
   <!-- Before -->
   [SCREENSHOT: App Store listing for CareKeeper]

   <!-- After -->
   ![App Store listing](../images/app-store-listing.png)
   ```
4. **Commit and push**:
   ```bash
   git add docs/images/
   git add docs/**/*.md
   git commit -m "docs: Add screenshots"
   git push
   ```

---

## Troubleshooting

### Build Fails with "Command not found: mkdocs"

**Solution:** Install dependencies first:
```bash
pip3 install -r requirements.txt
```

### Build Fails with "Module not found: material"

**Solution:** Reinstall MkDocs Material:
```bash
pip3 install --upgrade mkdocs-material
```

### Changes Not Appearing on Site

**Solution:**
1. Check build logs in Cloudflare Pages dashboard
2. Verify files committed and pushed to correct branch
3. Hard refresh browser (Cmd+Shift+R or Ctrl+F5)
4. Check "Latest Deployments" in Cloudflare dashboard

### Site Shows Wrong Version

**Solution:** Cloudflare caches aggressively:
1. Cloudflare Pages > Project > Settings > Builds & deployments
2. Trigger manual deployment
3. Or wait 5-10 minutes for CDN cache to expire

### Custom Domain Not Working

**Solution:**
1. Verify DNS CNAME points to `*.pages.dev` domain
2. Check SSL/TLS encryption mode in Cloudflare (should be "Full")
3. Wait up to 24 hours for DNS propagation
4. Check Cloudflare DNS dashboard for any errors

---

## Best Practices

### Branch Strategy

**Option 1: Dedicated docs branch**
- Pros: Clean separation, can deploy independently
- Cons: Documentation may drift from code

**Option 2: Same branch as code**
- Pros: Documentation stays in sync with code
- Cons: Code changes trigger doc rebuilds

**Recommendation:** Use dedicated `documentation` branch initially, merge to `main` before public release.

### Deployment Frequency

- **Content updates:** Deploy immediately (quick builds)
- **Configuration changes:** Test locally first
- **Major rewrites:** Use PR previews before merging

### Performance

- **Enable Cloudflare caching** (automatic with Cloudflare Pages)
- **Optimize images:** Use WebP format, compress before committing
- **Lazy load images:** Use MkDocs image optimization plugins if needed

### SEO

MkDocs Material includes SEO defaults, but you can enhance:

1. **Add meta descriptions** in frontmatter:
   ```markdown
   ---
   description: Learn how to track activities in CareKeeper
   ---
   ```

2. **Add sitemap:** Already generated by MkDocs at `/sitemap.xml`

3. **Submit to search engines:**
   - Google Search Console: Submit sitemap
   - Bing Webmaster Tools: Submit sitemap

---

## Monitoring

### Analytics (Optional)

To add Google Analytics:

1. **Edit `mkdocs.yml`**:
   ```yaml
   extra:
     analytics:
       provider: google
       property: G-XXXXXXXXXX
   ```

2. **Commit and deploy**

### Uptime Monitoring

Use Cloudflare Analytics (free) or external services:
- UptimeRobot (free tier)
- Pingdom
- StatusCake

---

## Cost Estimate

**Cloudflare Pages (Recommended):**
- Free tier: Unlimited requests, 500 builds/month, unlimited bandwidth
- Pro tier ($20/month): Advanced features not needed for docs

**Total Cost:** **$0/month** for documentation hosting

---

## Support

**Documentation Issues:**
- Check this file
- Review [MkDocs documentation](https://www.mkdocs.org/)
- Check [Material for MkDocs docs](https://squidfunk.github.io/mkdocs-material/)

**Cloudflare Issues:**
- [Cloudflare Pages docs](https://developers.cloudflare.com/pages/)
- [Cloudflare Community](https://community.cloudflare.com/)

**CareKeeper-Specific:**
- Open GitHub issue
- Contact maintainers

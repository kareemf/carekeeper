# ADR 006: Cloudflare Pages for Documentation Hosting

**Status:** Accepted

**Date:** 2025-10-28

**Deciders:** Development Team

---

## Context

CareKeeper requires a user-facing documentation site for:
- Installation and setup guides (tutorials)
- Feature documentation (how-tos)
- Conceptual explanations
- API/feature reference

### Requirements

1. **Private Repository Compatibility**: Documentation site must be publicly accessible while keeping source code private during development
2. **Automatic Deployment**: Changes pushed to git should automatically deploy
3. **Preview Deployments**: Pull requests should generate preview URLs
4. **Cost**: Free or minimal cost for documentation hosting
5. **Performance**: Fast global CDN for good user experience
6. **HTTPS**: Automatic SSL certificate management
7. **Custom Domain Support**: Ability to use docs.carekeeper.com in the future

### Documentation Stack

Already decided (separate ADR could document this):
- **MkDocs Material** for static site generation
- **Diataxis Framework** for documentation structure
- **Build Output**: Static HTML/CSS/JS in `site/` directory

---

## Decision

Use **Cloudflare Pages** as the primary documentation hosting platform.

**Production URL**: `carekeeper-docs.pages.dev` (or custom domain later)

**Deployment Configuration**:
```yaml
Build command: pip install -r requirements.txt && mkdocs build
Build output directory: site
Root directory: (empty)
Production branch: main (or documentation)
```

---

## Consequences

### Positive

1. **✅ Private Repo Support**: Works seamlessly with private GitHub repositories
   - Documentation site is public
   - Source code remains private
   - No special configuration needed

2. **✅ Zero Cost**: Free tier includes:
   - Unlimited bandwidth
   - 500 builds/month (sufficient for docs)
   - Unlimited requests
   - No credit card required

3. **✅ Automatic Deployments**:
   - Push to production branch → Deploys to production
   - Open pull request → Creates preview deployment
   - Close pull request → Deletes preview
   - 2-3 minute build times

4. **✅ Global Performance**:
   - Fast global CDN with edge caching
   - Automatic cache invalidation on deployment
   - Better performance than GitHub Pages

5. **✅ HTTPS by Default**:
   - Automatic SSL certificate provisioning
   - HTTPS enforced by default
   - No manual certificate management

6. **✅ Custom Domain Support**:
   - Easy CNAME setup for docs.carekeeper.com
   - Automatic SSL for custom domains
   - Can migrate later without changing infrastructure

7. **✅ Developer Experience**:
   - Simple GitHub integration
   - Clear build logs in dashboard
   - Preview URLs for testing before merge

### Negative

1. **⚠️ Vendor Lock-in (Minimal)**:
   - Not critical: Site is static HTML, can migrate to any host
   - Standard MkDocs build, portable to Netlify/Vercel/nginx
   - Migration effort: ~30 minutes to reconfigure CI/CD

2. **⚠️ Build Environment Constraints**:
   - Python version may need pinning if Cloudflare updates environment
   - Mitigation: Specify Python version in `.python-version` if needed

3. **⚠️ 500 Builds/Month Limit**:
   - Could hit limit with frequent documentation updates
   - Unlikely: Even with 3 updates/day = 90 builds/month
   - Can batch documentation updates if needed

### Neutral

- **Learning Curve**: Minimal - similar to Netlify/Vercel
- **Community Support**: Large Cloudflare community, good documentation

---

## Alternatives Considered

### 1. GitHub Pages

**Pros**:
- Free
- Integrated with GitHub
- Automatic HTTPS

**Cons**:
- ❌ Only works with **public repos** (or GitHub Pro for private)
- ❌ Slower CDN than Cloudflare
- ❌ More complex custom domain setup
- ❌ No PR preview deployments

**Verdict**: Rejected due to private repository requirement.

### 2. Netlify

**Pros**:
- Works with private repos
- Free tier
- Good GitHub integration
- Similar features to Cloudflare Pages

**Cons**:
- Lower free tier bandwidth (100GB/month vs unlimited)
- Fewer global edge locations than Cloudflare
- Build minutes limit on free tier (300 minutes/month)

**Verdict**: Viable alternative, but Cloudflare Pages offers better free tier.

### 3. Vercel

**Pros**:
- Works with private repos
- Fast CDN
- Good developer experience

**Cons**:
- Smaller free tier (100GB bandwidth/month)
- Primarily optimized for Next.js (works with static sites but not ideal)
- More complex pricing after free tier

**Verdict**: Works but less optimal for static documentation sites.

### 4. Self-Hosted (nginx)

**Pros**:
- Full control
- No vendor lock-in
- Can use existing infrastructure

**Cons**:
- ❌ Requires server maintenance
- ❌ Manual SSL certificate management
- ❌ Manual deployment setup (rsync/CI scripts)
- ❌ No automatic PR previews
- ❌ Cost: ~$5-10/month for VPS
- ❌ No global CDN (without additional cost)

**Verdict**: Rejected - unnecessary complexity and cost for static documentation.

### 5. ReadTheDocs

**Pros**:
- Specialized for documentation
- Free for open source

**Cons**:
- ❌ Requires public repository for free tier
- ❌ Less flexible than MkDocs + Pages
- ❌ Limited customization

**Verdict**: Rejected due to private repository requirement.

---

## Implementation

### Phase 1: Initial Setup (Completed)

1. ✅ Created `mkdocs.yml` configuration
2. ✅ Created `requirements.txt` with dependencies
3. ✅ Created `scripts/build-docs.sh` and `scripts/serve-docs.sh`
4. ✅ Documented deployment process in DEPLOYMENT.md (now this ADR)

### Phase 2: Cloudflare Pages Setup (Pending)

1. Create Cloudflare account
2. Connect GitHub repository
3. Configure build settings
4. Deploy initial version
5. Update `HelpView.swift` with production URL

### Phase 3: Content & Screenshots (Ongoing)

1. Add real screenshots to replace placeholders
2. Test all documentation links
3. Verify mobile responsiveness

### Phase 4: Custom Domain (Optional/Future)

1. Purchase/configure docs.carekeeper.com
2. Add custom domain in Cloudflare Pages
3. Update CNAME DNS records
4. Verify SSL certificate provisioning

---

## Monitoring & Maintenance

### Build Monitoring
- Check Cloudflare Pages dashboard for build failures
- Set up Slack/email notifications for failed builds

### Content Updates
- Edit markdown files in `docs/`
- Preview locally with `./scripts/serve-docs.sh`
- Commit and push → Auto-deployment

### Performance
- Monitor via Cloudflare Analytics (free)
- Use Lighthouse for page performance audits

---

## Decision Rationale

**Why Cloudflare Pages over others?**

1. **Private Repo Requirement**: GitHub Pages eliminated
2. **Cost**: Free tier sufficient, eliminates Vercel/self-hosted
3. **Performance**: Better CDN than Netlify, no setup needed vs self-hosted
4. **Developer Experience**: Automatic deployments, PR previews, simple setup
5. **Portability**: Static HTML output can migrate anywhere if needed

**Risk Assessment**: Low
- Easy to migrate if needed (static site)
- Free tier meets all requirements
- Battle-tested infrastructure (powers millions of sites)

---

## References

- [Cloudflare Pages Documentation](https://developers.cloudflare.com/pages/)
- [MkDocs Material Deployment Guide](https://squidfunk.github.io/mkdocs-material/publishing-your-site/)
- Internal: `scripts/build-docs.sh`, `scripts/serve-docs.sh`
- Internal: `mkdocs.yml` configuration

---

## Deployment Guide

For detailed deployment instructions, see sections below:

### Quick Start

```bash
# Local preview
pip3 install -r requirements.txt
./scripts/serve-docs.sh

# Build for production
./scripts/build-docs.sh
```

### Cloudflare Pages Setup

1. **Push to GitHub**:
   ```bash
   git push origin main
   ```

2. **Create Cloudflare Account**: [dash.cloudflare.com](https://dash.cloudflare.com)

3. **Create Pages Project**:
   - Pages > Create a project
   - Connect to GitHub
   - Select CareKeeper repository

4. **Configure Build**:
   ```
   Project name: carekeeper-docs
   Production branch: main
   Build command: pip install -r requirements.txt && mkdocs build
   Build output directory: site
   ```

5. **Deploy**: Click "Save and Deploy"

### Automatic Deployments

- Push to production branch → Deploys to production
- Open PR → Creates preview deployment
- Close PR → Deletes preview

### Troubleshooting

**Build fails with "Command not found: mkdocs"**:
```bash
pip3 install -r requirements.txt
```

**Changes not appearing**:
1. Check build logs in Cloudflare dashboard
2. Verify commit pushed to correct branch
3. Hard refresh browser (Cmd+Shift+R)

**Site shows wrong version**:
- Wait 5-10 minutes for CDN cache to expire
- Or trigger manual deployment in Cloudflare dashboard

---

## Notes

- This ADR supersedes the previous DEPLOYMENT.md guide
- The decision can be revisited if requirements change (e.g., need for server-side rendering)
- Custom domain setup is optional and can be added later without infrastructure changes

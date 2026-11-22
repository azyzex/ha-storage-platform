# Build the static site, then serve it with an unprivileged nginx (runs as non-root on port 8080).
FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# Trivy flagged fixable CRITICAL CVEs in 1.27-alpine and still 5 in 1.30.6-alpine (brotli, nginx HTTP/2):
# use the newest line AND upgrade the OS packages at build time, then drop back to the unprivileged user.
FROM nginxinc/nginx-unprivileged:1.31.7-alpine
USER root
RUN apk upgrade --no-cache
USER 101
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080

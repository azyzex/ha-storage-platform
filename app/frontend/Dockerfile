# Build the static site, then serve it with an unprivileged nginx (runs as non-root on port 8080).
FROM node:22-alpine AS build
WORKDIR /src
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

# 1.27-alpine (Alpine 3.21.3) had 3 fixable CRITICAL CVEs flagged by Trivy; 1.30.x is the current stable line.
FROM nginxinc/nginx-unprivileged:1.30.6-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /src/dist /usr/share/nginx/html
EXPOSE 8080

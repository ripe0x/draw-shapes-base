# Minimal keeper image: docker build -f ops/keeper/Dockerfile -t draw-shapes-keeper .
# docker run --env-file keeper.env -v $PWD/deployments:/app/deployments:ro -p 9464:9464 draw-shapes-keeper
FROM node:22-alpine
WORKDIR /app
COPY web/package.json web/package-lock.json* web/
RUN cd web && npm ci --omit=dev --ignore-scripts
COPY web/scripts web/scripts
USER node
CMD ["node", "web/scripts/keeper.mjs"]

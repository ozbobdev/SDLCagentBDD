FROM node:20-alpine
WORKDIR /app
COPY models ./models
COPY router ./router
COPY orchestrator ./orchestrator
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "orchestrator/server.js"]

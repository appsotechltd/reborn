FROM golang:1.26 AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/reborn ./cmd/reborn

FROM gcr.io/distroless/static-debian12
COPY --from=build /out/reborn /reborn
ENV ADDR=:8080
EXPOSE 8080
ENTRYPOINT ["/reborn"]
CMD ["serve"]

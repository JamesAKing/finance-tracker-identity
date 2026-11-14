FROM quay.io/keycloak/keycloak:26.8.2-2 AS build
ENV KC_DB=postgres
ENV KC_HEALTH_ENABLED=true
ENV KC_HTTP_RELATIVE_PATH=/auth
RUN /opt/keycloak/bin/kc.sh build

FROM quay.io/keycloak/keycloak:26.8.2-2
COPY --from=build /opt/keycloak/ /opt/keycloak/
COPY --chmod=755 keycloak/entrypoint.sh /opt/keycloak/bin/entrypoint.sh
COPY keycloak/realm.json /opt/keycloak/data/import/realm.json
ENV KC_HTTP_ENABLED=true
ENV KC_PROXY_HEADERS=xforwarded
USER 1000:0
EXPOSE 8080 9000
HEALTHCHECK --interval=15s --timeout=5s --start-period=90s --retries=5 \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/9000 && printf 'GET /auth/health/ready HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && head -n 1 <&3 | grep -q ' 200 '"]
ENTRYPOINT ["/opt/keycloak/bin/entrypoint.sh"]
CMD ["start", "--optimized", "--import-realm"]

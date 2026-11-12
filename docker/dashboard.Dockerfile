# The status page: a static page and its icon, plus the reviewer's feed mounted at /srv/status.
FROM busybox:1.37.0@sha256:a7dbc319b1438115a207e11930dc4bb3e643dcb3ec0bdd694bb36cd8fad289ec

COPY dashboard/index.html dashboard/favicon.svg /srv/
RUN mkdir /srv/status && chown 1000:1000 /srv/status
USER 1000:1000
CMD ["httpd", "-f", "-p", "8080", "-h", "/srv"]

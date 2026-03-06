FROM pretix/standalone:stable
USER root

# Obrigamos o Django a reconhecer o idioma durante a compilação
ENV PRETIX_PRETIX_LANGUAGES="en,pt-br"
ENV PRETIX_LANGUAGES_ALLOW_INCUBATING="pt-br"

# Compila o arquivo JS faltante e atualiza o manifesto do sistema
RUN pretix compilejsi18n
RUN pretix collectstatic --noinput

USER pretixuser

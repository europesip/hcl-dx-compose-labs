# Cómo contribuir

[English](CONTRIBUTING.md) · **Español**

Estos labs son código abierto (Apache License 2.0, ver [LICENSE](LICENSE) y [NOTICE](NOTICE)).
Cualquiera puede contribuir: correcciones, labs nuevos, mejores guías, traducciones, soporte para
otras plataformas o mejoras del [asistente de configuración](https://europesip.github.io/hcl-dx-compose-labs/about.html?lang=es).

## Cómo contribuir

1. Abre una [issue](https://github.com/europesip/hcl-dx-compose-labs/issues) describiendo el problema
   o la mejora (para correcciones pequeñas puedes ir directamente al paso 2).
2. Haz un fork del repositorio, crea una rama y haz tus cambios.
3. Pruébalos (ver abajo) y abre una pull request explicando qué cambia y cómo lo has probado.

## Normas

- **Scripts**: comentarios y mensajes en inglés; idempotentes (se pueden ejecutar dos veces); todos
  los valores vienen de `env.sh` / `env.example.sh`, nunca nombres, hosts o StorageClasses fijos.
- **Guías**: siempre en los dos idiomas, `GUIDE.md` (inglés) y `GUIDE.es.md` (español), y lo mismo
  para el `README` y `docs/`.
- **Prueba desde cero** antes de proponer un cambio en un lab: `common/99-cleanup.sh` y los labs de
  nuevo, en un clúster o en la PoC del Lab 0.
- **Nunca subas** `env.sh`, credenciales, certificados, los charts de HCL (`charts/`) ni imágenes de
  HCL. Están en `.gitignore`; revisa `git status` antes de cada commit.
- **Alcance**: los labs son una PoC para aprender. El *tuning* de producción queda fuera (ver el aviso
  del README).
- **Atribución**: conserva el fichero [NOTICE](NOTICE) y las menciones a EUROPESIP como autor
  original. Puedes añadirte como colaborador.

## Mantener el asistente de configuración

El asistente está en [`docs/index.html`](docs/index.html) (el asistente) y
[`docs/about.html`](docs/about.html) (su página de presentación), publicados en GitHub Pages. Su
código fuente también está en su propio repositorio,
[europesip/hcl-dx-compose-labs-wizard](https://github.com/europesip/hcl-dx-compose-labs-wizard):
**las dos copias tienen que ser idénticas.**

La opción C del asistente (la carpeta autónoma `dx-install/`) lleva **una copia de 28 ficheros de los
labs** (values, properties, LDIF, servidor MCP...) en el bloque `LAB TEMPLATES` de
`docs/index.html`, porque los rellena con los valores del usuario en el navegador. Cuando cambies
alguno de esos ficheros:

```bash
tools/sync-wizard-templates.py            # copia los ficheros de los labs en docs/index.html
tools/sync-wizard-templates.py --check    # solo avisa si la copia está desfasada
```

Después copia `docs/index.html` y `docs/about.html` al repositorio del asistente y sube los dos
repositorios. La lista de ficheros incluidos está al principio de
[`tools/sync-wizard-templates.py`](tools/sync-wizard-templates.py). `setup-postgres-dx.sql` no se
incluye a propósito: no se publica.

Para probar el asistente: abre `docs/index.html` en un navegador, genera las tres opciones y, para
la opción C, ejecuta el `install.sh` generado en un clúster vacío.

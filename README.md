# dei_multichar

Selector de personajes con diseno glassmorphism para FiveM. Parte del ecosistema Dei.

## Caracteristicas

- Seleccion de personajes con slots visuales
- Creacion de personajes con formulario completo
- Eliminacion de personajes con confirmacion
- Camara cinematica durante la seleccion
- Soporte ESX y QBCore
- Sincronizacion de temas con dei_hud
- 4 temas: dark, midnight, neon, minimal
- Modo claro/oscuro

## Instalacion

1. Copiar `dei_multichar` a tu carpeta de resources
2. Configurar `config.lua` segun tu framework
3. Agregar `ensure dei_multichar` a tu server.cfg
4. Asegurar que se inicia ANTES de tu recurso de spawn

## Configuracion

Editar `config.lua` para ajustar:
- Framework (esx/qbcore)
- Maximo de personajes
- Coordenadas de camara y ped
- Nacionalidad por defecto

## Dependencias

- ESX o QBCore
- dei_hud (opcional, para sincronizacion de temas)

## Estructura

```
dei_multichar/
├── fxmanifest.lua
├── config.lua
├── README.md
├── LICENSE
├── .gitignore
├── client/
│   ├── main.lua
│   ├── framework.lua
│   └── nui.lua
├── server/
│   ├── main.lua
│   └── framework.lua
└── html/
    ├── index.html
    └── assets/
        ├── css/
        │   ├── themes.css
        │   └── styles.css
        ├── js/
        │   └── app.js
        └── fonts/
            ├── Gilroy-Light.otf
            └── Gilroy-ExtraBold.otf
```

## Licencia

MIT License - Dei

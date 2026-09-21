# Ficha de App Store

Textos para pegar en App Store Connect. Idioma principal: **español (México)**.

---

## Nombre  *(máx. 30)*

```
MorseTrainer
```

## Subtítulo  *(máx. 30)*

```
Aprende código Morse de oído
```

> Lleva «código Morse» a propósito: el subtítulo se indexa, y así las palabras
> clave no gastan caracteres en repetirlo.

## Palabras clave  *(máx. 100, separadas por coma y sin espacios)*

```
cw,telegrafía,radioaficionado,ham,koch,farnsworth,señales,punto,raya,radio,escuchar,practicar
```

> No repiten «morse», «código» ni «aprende»: ya están en el nombre y el
> subtítulo, y Apple los indexa de ahí. Repetirlos sería tirar caracteres.

## Texto promocional  *(máx. 170, se puede cambiar sin revisión)*

```
Empiezas con dos letras y acabas con el alfabeto entero y los números. Sin tablas que memorizar: aprendes el ritmo, que es como se lee Morse de verdad.
```

---

## Descripción  *(máx. 4000)*

```
Aprende código Morse de oído, no de una tabla.

MorseTrainer usa el método Koch: empiezas con dos letras a velocidad final y solo aparece una nueva cuando reconoces las anteriores sin dudar.

POR QUÉ SUENA RÁPIDO DESDE EL PRIMER DÍA

Los caracteres van siempre a 18–25 palabras por minuto y lo que se alarga es el silencio entre ellos. Se llama temporización Farnsworth y existe por un motivo: si las letras sonaran despacio aprenderías a contar elementos, y ese hábito cuesta meses de quitar. Escuchándolas rápidas desde el principio aprendes el ritmo.

SE ADAPTA A TUS FALLOS

Si confundes la S con la H, las dos empiezan a aparecer más y juntas: contrastarlas es la única forma de deshacer una confusión. El teclado de respuesta tampoco es aleatorio — los distractores salen de los caracteres que tú ya confundes, para que no puedas aprobar por descarte.

CUATRO MODOS

• Campaña: 30 niveles, de dos letras al alfabeto completo y los números.
• Práctica libre: repaso sin corazones ni prisa.
• Contrarreloj: 60 segundos, tantas letras como puedas.
• Supervivencia: la velocidad sube hasta que se acaban los corazones.

OÍDO, TACTO Y VISTA

Cada señal suena, se siente en el Taptic Engine y puede salir por la linterna. Los tres canales funcionan a la vez y se encienden por separado: puedes jugar en silencio, o sin sonido si no oyes. El tono se ajusta entre 440 y 800 Hz por si tienes pérdida auditiva en alguna frecuencia.

TAMBIÉN TRANSMITES

No solo reconoces letras: las envías con un manipulador telegráfico en pantalla. Toque corto para punto, mantener para raya. El umbral entre uno y otro se calibra solo con tu propio pulso.

GANA COBRE

Al superar niveles ganas cobre, que se gasta en temas visuales y bancos de sonido. No es una moneda que se compre: solo se juega.

SIN LETRA PEQUEÑA

Sin anuncios. Sin compras dentro de la app. Sin cuenta. Sin conexión: funciona en modo avión. No recoge ningún dato — tu progreso se queda en tu iPhone y no sale de él.

Código abierto: github.com/sebasagua1/MorseTrainer
```

---

## Novedades de esta versión  *(máx. 4000)*

```
Primera versión.

• Campaña de 30 niveles con el método Koch, del alfabeto a los números.
• Cuatro modos: campaña, práctica libre, contrarreloj y supervivencia.
• Motor que insiste en las letras que confundes.
• Manipulador telegráfico para transmitir, no solo escuchar.
• Sonido, vibración y linterna, cada uno por separado.
```

---

## Campos de la ficha

| Campo | Valor |
|---|---|
| Categoría principal | Educación |
| Categoría secundaria | Juegos → Palabras |
| Clasificación por edad | 4+ |
| Precio | Gratis |
| Compras dentro de la app | Ninguna |
| Copyright | 2026 Sebastian Villegas Olaya |
| URL de soporte | https://sebasagua1.github.io/MorseTrainer/ |
| URL de privacidad | https://sebasagua1.github.io/MorseTrainer/privacidad.html |

> **Nota (20-09-2026).** La categoría «Juegos → Educativos» **ya no existe** en
> el catálogo de Apple. Las subcategorías de Juegos son: Acción, Aventura,
> Carreras, Cartas, Casino, Casual, Deportes, Estrategia, Familia, Mesa, Música,
> Palabras, Puzles, Rol, Simulación y Trivia. Se eligió **Palabras** por ser la
> que mejor describe un juego de reconocer caracteres. Se puede cambiar sin
> pasar por revisión.

## Otros campos que App Store Connect exige y no estaban aquí

| Campo | Valor | Dónde |
|---|---|---|
| Derechos de contenido | No contiene contenido de terceros | Información de la app |
| Disponibilidad | Los 175 países | Precios y disponibilidad |
| País base del precio | Estados Unidos (USD), 0,00 | Precios y disponibilidad |
| Publicación | **Manual**, no automática tras aprobar | Ficha de la versión |
| Capturas | Solo el juego 6,9" (1320x2868); Apple lo reutiliza para 6,5" | Ficha de la versión |
| Novedades | No aplica en una 1.0: la API lo rechaza | — |

## Sobre publicar solo en español

La ficha va en español porque **la app está en español**. Añadir una ficha en
inglés multiplicaría las descargas y también las malas reseñas: quien llegue
buscando *learn morse code* se encontrará una interfaz que no entiende.

Si quieres alcance internacional, el orden correcto es localizar la app primero
—son unas pocas decenas de cadenas más el banco de palabras— y añadir la ficha
en inglés después. No al revés.

## Privacidad de la app

Responder **«No se recopilan datos»**. No hay red, ni analítica, ni SDK de
terceros: está comprobado en el código y declarado en `PrivacyInfo.xcprivacy`.

## Notas para el revisor

```
No hace falta cuenta ni credenciales: la app arranca y se juega.

La app usa la linterna como canal opcional para transmitir Morse con destellos.
Se activa en Ajustes › Canales de salida › Linterna. No accede a la cámara ni
captura imágenes.

Todo funciona sin conexión. No hay servidores ni compras dentro de la app: el
cobre es una moneda que solo se gana jugando.
```

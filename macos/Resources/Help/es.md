# Ayuda de Band·je
Band·je graba conversaciones en tu Mac y las convierte en texto. Vive en la barra de menús: la pequeña cinta de casete arriba a la derecha. Todo ocurre en tu Mac.

## Grabar una conversación {#record}
Pulsa ⌃⌥⌘R para empezar y otra vez ⌃⌥⌘R para parar.

Band·je graba dos cosas a la vez: tu micrófono y todo el sonido que reproduce tu Mac. Funciona con cualquier app de llamadas, como FaceTime, Zoom, Teams, Meet o una llamada de teléfono a través de tu Mac. Band·je no graba tu pantalla.

- Mientras graba, el casete de la barra de menús se vuelve rojo, sus bobinas giran y el tiempo corre a su lado en rojo.
- Tu Mac no entra en reposo mientras Band·je graba.
- La primera vez, macOS pide permiso para grabar el audio de tu Mac. Permítelo; si no, Band·je solo oye tu micrófono.
- Si tu micrófono se queda en silencio seis segundos, o cierras la tapa mientras usas el micrófono integrado, Band·je te avisa y te ofrece cambiar a otro micrófono.

Avisa a los demás de que estás grabando. En algunos países, y en el ámbito profesional, la ley lo exige, y a veces también necesitas su consentimiento. Eres responsable de cumplir la ley que te corresponde. Band·je te lo recuerda una vez, antes de tu primera grabación.

### Dónde se guardan tus grabaciones
Cada grabación tiene su propia carpeta en `~/Music/Bandje` (o en la carpeta que elegiste en [Ajustes](#settings), o en iCloud Drive › Band·je si [sincronizas con iCloud](#settings)), con el día y la hora como nombre, por ejemplo `Grabación 6 nov 14.32`. Tu iPhone nombra sus grabaciones de la misma forma. En la carpeta:

- el audio (`.m4a`): tú en el canal izquierdo, los demás en el derecho
- la transcripción (`.md`), legible en cualquier app de texto o Markdown
- los datos en bruto (`.json`) con el momento de cada palabra
- los resúmenes, como archivos `.md`

Abre una grabación en la [ventana de Band·je](#player). Elige **Abrir carpeta de grabaciones** en el menú para ver los archivos. Si Band·je o tu Mac se detienen de forma inesperada durante una grabación, Band·je te ofrece guardarla la próxima vez que se abra.

## Transcripciones {#transcripts}
Cuando dejas de grabar, Band·je escribe lo que se ha dicho y quién lo ha dicho.

El menú muestra el progreso. Puedes empezar una grabación nueva mientras Band·je transcribe. Cuando la transcripción está lista, aparece una pequeña marca verde en el casete de la barra de menús y el menú dice **Transcripción lista**: haz clic para abrir la grabación en la ventana de Band·je. La marca desaparece cuando abres el menú.

- Lo que dices tú aparece como **Yo**. Lo que dicen los demás aparece como **Otra parte**.
- Cuando hablan varias personas en la otra parte, Band·je las distingue: **Hablante 1**, **Hablante 2**, etc. Ponles nombre con [Nombrar hablantes](#speakers).
- Lo mismo ocurre con varias personas alrededor de tu Mac, en una reunión en una misma mesa: en lugar de **Yo** pasan a ser **Hablante 1**, **Hablante 2**, etc.
- Band·je entiende 25 idiomas, entre ellos inglés, neerlandés, alemán, francés, español, italiano, portugués, polaco, ruso y ucraniano. No hace falta elegir el idioma.

Para obtener el mejor resultado, usa auriculares durante la llamada. Sin ellos, tu micrófono también capta a la otra parte por los altavoces. Band·je filtra casi todo, pero no todo.

### Transcribir otro archivo
Elige **Transcribir archivo…** para transcribir cualquier archivo de audio, como una nota de voz de tu iPhone. Band·je copia el audio a su propia carpeta dentro de tu carpeta de grabaciones y guarda al lado la transcripción. El original se queda donde estaba.

## Nombrar hablantes {#speakers}
Pon los nombres reales a los hablantes de una transcripción.

Abre la grabación en la [ventana de Band·je](#player) y elige **Nombrar hablantes…** en **Más**, o elige **Nombrar hablantes…** en el menú: abre la grabación actual. Para trabajar con una grabación anterior desde el menú, elige antes **Grabaciones recientes**.

Para cada hablante ves su frase más larga. Haz clic en el botón de reproducir para oír ese fragmento, escribe un nombre y haz clic en **Guardar**. Band·je actualiza la transcripción y cualquier resumen posterior. Deja un campo vacío para mantener la etiqueta.

En una línea telefónica con menú o música de espera, Band·je a veces oye más hablantes de los que había. Pon el mismo nombre a dos etiquetas, o deja la que sobra como está.

## La ventana de Band·je {#player}
Todas tus grabaciones en una ventana: escucha, lee a la vez, busca, nombra a los hablantes, resume y comparte.

Elige **Abrir Band·je** en el menú (⌘O). La ventana también se abre cuando abres Band·je tú mismo, por ejemplo desde Launchpad o Spotlight. **Abrir en Band·je** abre la grabación actual. Mientras la ventana está abierta, Band·je está en el Dock y en ⌘Tab; ciérrala y Band·je vuelve a estar solo en la barra de menús. Activa **Siempre en el Dock** en [Ajustes](#settings) para mantener el icono. La primera vez, la ventana se abre siempre, con los permisos, cada uno con su botón. Si cierras la ventana, Band·je sigue en la barra de menús; sal de Band·je desde ese menú.

- A la izquierda: tus grabaciones por día, con la hora, la duración y las primeras palabras de la transcripción. La búsqueda encuentra títulos y palabras de las transcripciones. Abajo está **Iniciar grabación**; mientras grabas, la nueva grabación aparece arriba con un punto rojo y, al detenerla, la ventana la abre.
- A la derecha: la grabación con el casete, la barra de posición y el botón de reproducir (barra espaciadora). Haz clic en una frase para escuchar desde ahí; durante la reproducción se resalta la frase que oyes y la transcripción la sigue. **Buscar en la transcripción** (⌘F) encuentra palabras.
- Junto a **Transcripción** está la pestaña **Resumen**. Si aún no hay resumen, ahí está **Resumir**: elige una plantilla, consulta [Resúmenes](#summaries). Cada resumen tiene su propia pestaña; **Otro resumen** crea otro.
- ¿Aún no hay transcripción (por ejemplo, de una grabación de tu iPhone)? Haz clic en **Transcribir**.
- **Compartir**: **Audio…**, **Transcripción (.md)…**, **Transcripción en PDF…** o **Página web con audio…**: un archivo con el reproductor, la transcripción, los resúmenes y el audio, que funciona en cualquier navegador, también sin conexión. **Página web con audio, compacta (para correo)…** reduce el audio. La página tiene un enlace a band.je y nada más.
- En papel: **Imprimir…** (⌘P, o en **Compartir**) imprime la transcripción, igual que el PDF.
- **Más**: **Nombre y color…** (o haz clic en el título del casete): el nombre y el color del casete, **Nombrar hablantes…**, **Mostrar en el Finder**, **Eliminar…** (a la Papelera).
- También puedes eliminar una grabación desde la lista: haz clic derecho en ella y elige **Eliminar…**, o selecciónala y pulsa ⌫. Band·je pregunta antes.

## Dictado {#dictation}
Pulsa ⌃⌥⌘D, habla y el texto aparece donde está tu cursor: en un chat, un correo, un editor o Terminal.

Hay dos formas de usar el atajo:

- **Pulsar** ⌃⌥⌘D: Band·je escucha hasta que pulses Return u otra vez ⌃⌥⌘D. El Return no se envía a la app.
- **Mantener** ⌃⌥⌘D: Band·je escucha mientras mantienes pulsadas las teclas y pega el texto al soltarlas.

Pulsa Esc para cancelar. El icono de la barra de menús se vuelve naranja mientras Band·je escucha, con el tiempo al lado. Un dictado puede durar hasta cinco minutos; en los últimos 30 segundos el tiempo parpadea.

### Pegar
El texto siempre está en el portapapeles. Para pegarlo por ti, Band·je necesita permiso para enviar una pulsación de teclas (⌘V): elige **Activar pegado automático…** en el menú, o ve a Ajustes del Sistema > Privacidad y seguridad > Accesibilidad y activa Band·je. Sin ese permiso, pegas tú con ⌘V.

macOS solo informa a Band·je de este permiso tras reiniciarlo. ¿Lo acabas de activar? Elige **Reiniciar Band·je para el pegado automático** en el menú, o **Reiniciar Band·je** en [Ajustes](#settings).

Si oyes un sonido breve en lugar de pegarse el texto, un campo de contraseña u otra app ha activado la entrada segura (la Entrada de teclado segura de Terminal, un gestor de contraseñas). macOS bloquea entonces el pegado; el texto está en el portapapeles, así que pulsa tú ⌘V.

No se guarda nada de lo que dictas.

## Resúmenes {#summaries}
Band·je puede resumir una conversación con el formato que elijas, con Apple Intelligence en tu Mac.

Los resúmenes requieren macOS 26 o posterior con Apple Intelligence activado. Sin eso, el menú **Resumir** no aparece y Band·je funciona como siempre.

1. Elige **Resumir** en el menú.
2. En **Elige una plantilla**, elige una. Band·je resume la grabación actual. Para resumir otra, selecciónala antes en **Grabaciones recientes**.
3. Mientras Band·je trabaja, aparecen destellos morados en la barra de menús. Coloca el puntero encima para ver el progreso.
4. Cuando termina, aparece una pequeña marca verde en el casete y el menú dice **Resumen listo**. Si la ventana de Band·je está abierta, muestra la grabación.

También puedes empezar en la [ventana de Band·je](#player): elige **Resumir** junto a las pestañas y elige una plantilla.

El resumen se guarda junto a la transcripción como `<nombre> resumen <plantilla>.md`. Un resumen tarda desde unos segundos hasta un minuto aproximadamente. Las conversaciones largas se resumen por partes.

El resumen se escribe en el idioma de la conversación. Apple Intelligence resume en inglés, neerlandés, alemán, francés, español, italiano, portugués y algunos idiomas más, pero todavía no en polaco, ruso ni ucraniano.

El modelo de tu Mac es pequeño. Se ciñe a lo que se dijo, pero puede pasar por alto detalles. Comprueba los datos importantes en la transcripción.

Band·je incluye cuatro plantillas: una reunión, una entrevista de trabajo, una entrevista con un cliente y un resumen general. Para crear la tuya, consulta [Crear una plantilla](#templates).

## Crear una plantilla {#templates}
Crea tu propia plantilla para resúmenes: un archivo de texto con los encabezados que quieras.

Una plantilla es un archivo de texto normal (`.md` o `.txt`) en `~/Music/Bandje/Templates`. El nombre del archivo es el nombre que aparece en el menú **Resumir**.

Lo más rápido: con la ventana de Band·je abierta, elige **Resumir** > **Nueva plantilla** en la barra de menús. Band·je crea una plantilla nueva con dos encabezados y la abre; cámbiala, guárdala y ponle un nombre propio en el Finder.

### Empieza con una copia
Lo más fácil es copiar un ejemplo y modificarlo:

1. Elige **Resumir** > **Abrir carpeta de plantillas**.
2. Selecciona el ejemplo que más se parezca a lo que quieres, como `Meeting.md`.
3. Elige Archivo > Duplicar (⌘D) en el Finder y cambia el nombre de la copia, por ejemplo `Reunión semanal.md`.
4. Abre la copia en TextEdit u otra app de texto, cambia los encabezados y guárdala.

La nueva plantilla aparece enseguida en el menú **Resumir**. También puedes modificar los ejemplos o eliminarlos: Band·je solo los vuelve a poner si eliminas toda la carpeta Templates.

### Qué incluye una plantilla
Una lista de encabezados, cada uno con una línea sobre lo que va debajo:

- `## Decisiones` con la línea "Cada decisión como viñeta. Indica quién decidió."
- `## Tareas pendientes` con la línea "Quién, qué y cuándo."

Consejos:

- Sé concreto. "Expectativa salarial con las cantidades exactas" funciona mejor que "Salario".
- Limítate a unos cinco encabezados. El modelo de tu Mac es pequeño: con menos encabezados, mejores respuestas.
- Escribe "si se dijo" cuando algo puede no salir, para que Band·je no se lo invente.
- Los encabezados se quedan tal como los escribes. El texto sigue el idioma de la conversación.

## Micrófono y sonido {#devices}
Elige qué micrófono usas y adónde va el sonido de tu Mac, directamente desde el menú.

### Micrófono
El menú **Micrófono** muestra todos los micrófonos. El que está en uso tiene una marca y su nombre aparece debajo del ítem del menú. Al elegir uno cambias el micrófono de todo tu Mac, así que tu app de llamadas usa el mismo. Con la tapa cerrada, el micrófono integrado está apagado; Band·je lo indica.

### Salida de sonido
El menú **Salida de sonido** muestra todos los dispositivos que pueden reproducir sonido y define la salida de sonido de tu Mac. Band·je nunca la cambia por su cuenta.

Algunos micrófonos USB tienen conector para auriculares y también cuentan como altavoces. Cuando tus AirPods se desconectan, macOS puede enviar el sonido ahí. Elige tus altavoces en Salida de sonido para solucionarlo.

## Ajustes {#settings}
Atajos, la carpeta de grabaciones, los permisos, la apertura al iniciar sesión y el idioma de Band·je.

Elige **Ajustes…** en el menú.

### General
Activa **Abrir Band·je al iniciar sesión** y Band·je aparecerá solo en la barra de menús al iniciar sesión. **Siempre en el Dock** mantiene Band·je en el Dock, también sin la ventana. También puedes elegirlo en la ventana de bienvenida la primera vez que abres Band·je. Está desactivado hasta que lo actives. Si lo desactivas en Ajustes del Sistema > General > Ítems de inicio y extensiones, Band·je lo muestra aquí. Desactiva **Mostrar la ventana de Band·je al iniciar** y Band·je se queda en la barra de menús al iniciar.

Band·je sigue el idioma de macOS. Para usar otro idioma solo en Band·je, elígelo aquí y haz clic en **Reiniciar Band·je**. Cambian los menús, las ventanas, las transcripciones nuevas y la ayuda. **Igual que macOS** vuelve al idioma del sistema.

### Atajos de teclado
Haz clic en un campo y pulsa la nueva combinación. Debe incluir ⌘, ⌃ o ⌥, o ser una tecla de función. Esc cancela, y **Valores por omisión** recupera ⌃⌥⌘R y ⌃⌥⌘D.

Si otra app ya usa la combinación, Band·je te lo dice y mantiene la anterior.

### Sonido
Elige el **Micrófono** y la **Salida de sonido**, como en el menú de Band·je. Se aplica a todas las apps, también para llamar.

### Transcripción
**Transcribir automáticamente** transcribe cada grabación en cuanto la detienes. **Reconocer hablantes** distingue varias voces (Hablante 1, Hablante 2…); si está desactivado, solo obtienes Yo y Otra parte. Band·je reconoce el idioma solo.

### Almacenamiento
Activa **Sincronizar con iCloud** y tus grabaciones, transcripciones, resúmenes y plantillas estarán en iCloud Drive › Band·je, en tu iPhone y en tus otros Mac con la misma cuenta de Apple. Una grabación se hace primero en tu Mac y pasa a iCloud cuando la detienes. Band·je te pregunta si quieres trasladar también tus grabaciones existentes. Si lo desactivas, tu propia carpeta vuelve a ser la carpeta de grabaciones; no se elimina nada de iCloud, y Band·je te ofrece copiar las grabaciones de vuelta. Apple cifra iCloud Drive de extremo a extremo cuando la Protección de datos avanzada está activada.

Haz clic en **Cambiar…** y elige una carpeta, en cualquier lugar de tu Mac o en un disco externo. Las grabaciones nuevas y los archivos transcritos van ahí. Las grabaciones existentes se quedan donde están, igual que tus plantillas y los modelos de voz. **Usar ~/Music/Bandje** vuelve a la carpeta estándar.

Si la carpeta está en iCloud Drive, Dropbox u otro servicio en la nube (también el Escritorio y Documentos cuando están en iCloud), Band·je te avisa: tus grabaciones saldrán entonces de tu Mac a través de ese servicio.

### Acceso
Si Band·je puede usar el micrófono, pegar por ti y grabar el sonido de tu Mac, cada uno con su botón (**Permitir…** o **Abrir ajustes…**). Una marca verde significa permitido; el estado se actualiza solo cuando vuelves de Ajustes del Sistema. Consulta [Solución de problemas](#troubleshooting).

## Privacidad y red {#privacy}
Tu audio, tus transcripciones y tus resúmenes nunca salen de tu Mac.

- Sin cuenta, sin analíticas, sin seguimiento. Sin servidores nuestros.
- iCloud solo si activas [Sincronizar con iCloud](#settings): entonces tus grabaciones están en tu propio iCloud Drive, como tus otros archivos. Band·je nunca las ve.
- Todo se guarda en tu carpeta de grabaciones: `~/Music/Bandje`, salvo que hayas elegido otra. Elimina una carpeta y desaparece. Si eliges una carpeta en iCloud Drive u otro servicio en la nube, tus grabaciones van a ese servicio; Band·je te avisa antes.
- La transcripción, el reconocimiento de hablantes y el dictado se ejecutan en tu Mac.
- Los resúmenes solo usan el modelo de Apple Intelligence de tu Mac, nunca Private Cloud Compute de Apple.

El motor de voz de Desert Ant Labs comprueba su licencia a través de la red: como máximo una vez al mes por modelo de voz. Envía un ID de instalación aleatorio, la versión del modelo y del motor y el ID de la app. Nunca audio, nunca texto. **Acerca de Band·je** también lo indica.

## Memoria y almacenamiento {#resources}
Band·je es ligero: unos 60 a 70 MB de memoria mientras se ejecuta.

Los modelos de voz vienen con Band·je: unos 400 MB del tamaño de la app. Band·je nunca descarga nada por su cuenta.

Unos segundos después de abrirse, Band·je carga el modelo de voz en segundo plano, para que el dictado esté listo enseguida. La primera vez en un Mac tarda unos 20 segundos, porque macOS optimiza el modelo para tu chip. Después es rápido.

Una hora de audio ocupa unos 55 MB. Transcribirla requiere algo de memoria extra mientras dura.

## Solución de problemas {#troubleshooting}
Soluciones para lo que puede fallar.

### Comprueba primero los permisos
Muchos problemas se deben a que falta un permiso. Elige **Ajustes…** y mira en **Acceso**:

- **Micrófono**: necesario para grabar tu voz y para dictar.
- **Sonido de tu Mac**: necesario para grabar a la otra parte. macOS no deja que las apps lean este permiso, así que Band·je muestra lo que pasó en la última grabación: llegó sonido o hubo silencio. El silencio es normal si no sonaba nada.
- **Pegado automático**: necesario para pegar por ti el texto dictado.

Una marca verde significa permitido. Si no, haz clic en **Abrir ajustes…**, activa Band·je y vuelve; Band·je lo nota solo.

Cada vez que se abre, Band·je comprueba el micrófono y el pegado automático, y te avisa si falta alguno. ¿No necesitas el pegado automático? Marca **No volver a mostrar este mensaje**, o desactiva **Avisar al iniciar si falta algo** en Acceso.

### Falta la otra parte en la grabación
macOS no ha permitido que Band·je grabe el audio de tu Mac. Ve a Ajustes del Sistema > Privacidad y seguridad > Grabación de pantalla y del audio del sistema y activa Band·je en Solo grabación del audio del sistema.

### Falta mi propia voz
Revisa el menú **Micrófono**. Con la tapa cerrada, el micrófono integrado está apagado: elige otro. Si Band·je no tiene permiso para usar el micrófono, actívalo en Ajustes del Sistema > Privacidad y seguridad > Micrófono.

### No oigo nada después de quitarme los AirPods
macOS ha enviado el sonido a otro dispositivo, como un micrófono USB con conector para auriculares. Elige tus altavoces en **Salida de sonido**.

### La transcripción no tiene sentido
Probablemente la conversación está en un idioma que Band·je no conoce. Band·je no puede saberlo, así que escribe lo que cree haber oído.

### Hay más hablantes de los que había
Los menús telefónicos, la música de espera y las líneas de mala calidad pueden confundir el reconocimiento de hablantes. Pon los nombres correctos a las etiquetas en [Nombrar hablantes](#speakers).

### Resumir no aparece en el menú
Los resúmenes requieren macOS 26 o posterior con Apple Intelligence activado en Ajustes del Sistema > Apple Intelligence y Siri. El idioma de tu Mac y el de Siri deben coincidir.

### El atajo no funciona
Puede que otra app use la misma combinación. Elige otra en [Ajustes](#settings).

## Acerca de Band·je {#about}
Band·je está creado por Neurendal B.V. en los Países Bajos.

Reconocimiento de voz y de hablantes: Voz y Who de Desert Ant Labs, basados en NVIDIA Parakeet TDT 0.6B v3 y pyannote community-1 (CC BY 4.0). Resúmenes: Apple Intelligence.

Elige **Acerca de Band·je** en el menú para ver las versiones y los enlaces.

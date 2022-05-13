WebSockets con PHP + Javascript (Vanilla)
15 mayo, 2018 En Javascript, PHP
Tabla de contenidos	
TEORÍA
PRÁCTICA
EJEMPLO
RESUMEN
TEORÍA
La «idea feliz» de los webSockets es mantener una comunicación permanente entre servidor y clientes para recibir información desde la parte servidora sin tener que ser solicitada previamente por la parte cliente (Llamado notificación PUSH). Además, sería ideal que, en la parte servidora, existiese un único hilo que esté procesando información (por ejemplo, escuchando cambios de una BD o eventos lanzados por otros procesos) para mandar la información a todos los clientes a la vez sin consumir los recursos que requeriría para cada cliente por separado.

Lo primero que se plantea uno es ¿Cómo va a mantener la comunicación entre cada uno de los sockets PHP si realmente PHP, tal y como nos lo enseñan a todos, es un lenguaje basado en cliente-servidor? Es decir, el cliente realiza una petición al servidor, el script de PHP se ejecuta, devuelve un resultado y el script de PHP muere…

Tenemos:



Queremos:



Pues aquí es donde entra en juego el concepto de Servicio (Windows) o Demonios/Daemon (UNIX).

Se puede crear un proceso en el servidor que ejecute constántemente un script de PHP al cual se conecten los clientes. El script de PHP, que pasará a ser un servicio, mantiene abiertas las comunicaciones con todos los clientes en todo momento después de su conexión y la lógica del servicio se maneja enteramente desde este script (parecido a un «hilo principal de ejecución» en un servidor java). Este script sencillamente se ejecutará en un bucle infinito «while(true)«.

Pero la duda viene nuevamente ¿Cómo un script PHP en ejecución puede recibir información externa y aceptar conexiones de nuevos clientes sin ejecutar el script directamente (Que es lo que se haría al pedir una página web de contenido dinámico a través de una URL)? Esto se consigue mediante el conjunto de funciones de PHP para crear y manejar sockets (socket_*): el script de PHP creará un socket maestro (socket_create) que inicia, por así decirlo, un servicio/daemon en el Sistema Operativo con un puerto abierto (asignado manualmente mediante la función socket_bind). Este servicio de socket conseguirá que el script PHP reciba información del exterior (así como enviarla).



NOTA: Un socket no es más que una tubería de datos (pipeline) por donde se manda y recibe información de cualquier tipo. Cada socket tiene un puerto asociado con el que se identifica dentro del SO del servidor.

En esto se basa la comunicación persistente entre varios clientes y un script PHP.

El cliente entonces se conectará al servicio del SO a través del puerto que le hemos asignado al socket maestro, envía información de que quiere conectarse al socket, el script de PHP (que estará programado para leer constantemente las nuevas peticiones) lee el buffer del socket maestro, procesa la información y, si es correcta, abre un socket individual para ese nuevo cliente. El script PHP mantiene un array de los sockets abiertos a través de los cuales puede recibir y mandar información a cada cliente desde el mismo hilo de ejecución de PHP.



¡Voila! La magia está servida 🙂

Nótese que incluso otro proceso PHP del servidor podría también comunicarse con el hilo de ejecución del servicio foo.php ¡Pudiendo crear así una arquitectura orientada a eventos como por ejemplo publish/subscribe!.

PRÁCTICA
Recomiendo usar la biblioteca PHP-Websockets que se puede encontrar en github (https://github.com/ghedipunk/PHP-Websockets) para tener una base por la que empezar. Pero vamos a intentar comprender qué hace esta biblioteca.

Lo primero decir que la clase principal usada es WebSocketServer que se encuentra dentro del archivo «websockets.php». Esta clase usa a su vez la clase «WebSocketUser» (que no es más que la definición de un objeto con atributos que se deben guardar de cada cliente conectado por el socket) cuya definición se encuentra en users.php. Cada «WebSocketUser» será una conexión de un cliente al socket y la clase WebSocketServer almacenará a todos los usuarios conectados en el array «$users«.

El constructor de la clase WebSocketServer hace lo siguiente:

1.- Crea el «socket master». Es, por así decirlo, el socket que hace de servicio en el SO. Este socket es la puerta de comunicación con el mundo exterior, así que lo almacena como atributo de la clase y lo añade al array de sockets abiertos.

$this->master = socket_create(AF_INET, SOCK_STREAM, SOL_TCP);
2.- Pone unas opciones de comunicación al socket master:

socket_set_option($this->master, SOL_SOCKET, SO_REUSEADDR, 1);
3.- Le asigna una dirección IP y un puerto donde escuchar nuevas conexiones:

socket_bind($this->master, $addr, $port);
4.- Y le habilita para que escuche conexiones con un máximo de peticiones pendientes en cola (es el segundo parámetro, en este caso pone 20 conexiones por defecto como máximo). Si hay 20 peticiones pendientes de procesar y llega una petición más, esta última será desechada y el cliente recibirá el código de conexión correspondiente a «Conexión rechazada» (ECONNREFUSED):

socket_listen($this->master,20);
Luego, en su método «run()«, realiza un bucle infinito en el cual realiza las siguientes tareas principales:

1.- Lee el array de sockets (que en el inicio solo contendrá el socket master). El array de sockets se copia a la variable local «$read» ya que socket_select es una proce-función (función y procedimiento a la vez) que va a modificar el valor de la variable «$read» escribiendo en ella cuáles son los sockets que han dejado datos para ser leídos, así que no se desea que se modifique el array original de sockets, por lo que le pasamos una copia:

socket_select($read, null, null, 1);
2.- Ahora que en la variable «$read» se tienen los sockets que contienen algo interesante, los recorre con un foreach:

foreach ($read as $socket) { ... }
3.- Primero se pregunta si el socket seleccionado es el socket maestro (socket master). Si es así, significa que hay un cliente intentando realizar una conexión nueva, así que la intenta aceptar y, en caso de éxito, se crea un socket nuevo para el cliente y se añade al array de sockets:

if ($socket == $this->master) {
$client = socket_accept($socket);
if ($client < 0) {
//ERROR!!
continue;
}
else {
$this->connect($client); //Se añade al array de sockets
}
}
4.- En otro caso, si no es el socket maestro, lee el número de bytes recibidos con socket_recv. Si el resultado es false significa que se produjo un error, si el resultado es igual a 0 significa desconexión del cliente, en otro caso se comprueba que el cliente haya completado el handshake (esto es, leer la cabecera del paquete de la conexión y comprobar que es correcta), y si es así se empieza a trocear la información en frames para luego ser procesada ejecutando posteriormente el método abstracto «process(usuario, mensaje)» (sino, tiene que terminar de realizar el handshake):

else{ //Socket no es el socket master
$numBytes = socket_recv($socket, $buffer, $this->maxBufferSize, 0);
if ($numBytes === false) { //Error de conexión
$sockErrNo = socket_last_error($socket);
switch ($sockErrNo)
{ ... }
}
elseif ($numBytes == 0) { //Conexión perdida con el cliente
$this->disconnect($socket); //Elimina el socket del array de sockets
}
else {
//Procesar los datos recibidos, ya sea el handshake o los datos en sí mismos (Tras procesar los datos ejecutará el método abstracto process()).
//$this->process($user, $message).
}
}
NOTA: El handshake es lo primero que se envía al intentar realizar la conexión con el socket maestro. Es un string que debe tener el siguiente formato según el protocolo de conexión de los websockets en su versión nº 13:

"GET / HTTP/1.1\r\n" .
"Upgrade: websocket\r\n" .
"Connection: Upgrade\r\n" .
"Host: "./*HOST DESTINO*/."\r\n" .
"Origin: "./*HOST ORIGEN*/."\r\n" .
"Sec-WebSocket-Key: "./*ID ÚNICO EN B64*/."\r\n" .
"Sec-WebSocket-Version: 13\r\n\n";
EJEMPLO
Ahora vamos a realizar un ejemplo de WebSocket que simule una sala de chat (un usuario escribe un mensaje y le llega a todos los que estén conectados). Voy a usar XAMPP para el ejemplo.

ATENCIÓN en php.ini debe estar descomentada la línea «extension=php_sockets.dll» (o el equivalente para habilitar los sockets en tu instalación de php).

ATENCIÓN ya que los sockets van a intentar acceder a puertos de un servidor a través de un router, puede que tengáis que configurar el firewall que aplique en cada caso para tener el puerto abierto del socket maestro.

1.- Crear una clase que herede de WebSocketServer:

require_once('websockets.php');
class SalaChatServer extends WebSocketServer { ... }
2.- Redefinir la función process (que es la que se ejecuta tras recibir datos de un cliente) y redefinir las funciones «connected» y «closed«:

protected function process ($user, $message) {
echo 'user sent: '.$message.PHP_EOL;
foreach ($this->users as $currentUser) {
if($currentUser !== $user)
$this->send($currentUser,$message);
}
}
protected function connected ($user) {
echo 'user connected'.PHP_EOL;
}
protected function closed ($user) {
echo 'user disconnected'.PHP_EOL;
}
3.- Inicializar una instancia de la clase heredada que hemos llamado SalaChatServer para que escuche conexiones en localhost en el puerto 9000:

$chatServer = new SalaChatServer("localhost","9000");
try {
$chatServer->run();
}
catch (Exception $e) {
$chatServer->stdout($e->getMessage());
}
Este trozo de código lo guardamos en un archivo php llamado, por ejemplo, SalaChatServer.php.

IMPORTANTE: todos los archivos tanto de la biblioteca PHP-WebSockets como SalaChatServer.php se tienen que almacenar en una carpeta que no sea de acceso público desde internet ya que los clientes no tienen que acceder a estos archivos; los clientes solo se conectarán al socket abierto en el servidor que van a generar esos archivos. Yo en el ejemplo, usando XAMPP, lo voy a guardar en «C:\xampp\daemons\sala_chat».

Ejecutamos desde la consola de comandos (CMD) el archivo SalaChatServer.php usando php.exe:

«C:\xampp\php\php.exe» -q C:\xampp\daemons\sala_chat\SalaChatServer.php

¡Voila! Ya tenemos nuestro servicio PHP escuchando conexiones nuevas de manera indefinida. Nótese que ejecutando el script PHP mediante CMD no debería cerrarse nunca por timeout, y por tanto no hay que modificar el valor de timeout en php.ini.

Finalmente queda la parte cliente. Opto por usar JavaScript.

En HTML5, JavaScript ya incluye un objeto llamado «WebSocket» que realiza las tareas básicas para la comunicación por socket (incluyendo el handshake para la conexión). Sencillamente tenemos que instanciarlo indicando el host y asociándole los EventListener para las situaciones «onopen«, «onmessage» y «onclose«. Para mandar un mensaje se usa la función «WebSocket.send(String)«.

NOTA: Los WebSockets usan el protocolo TCP, así que se garantiza que los mensajes se mandan, se tratan y se reciben en orden.

1.- En nuestro ejemplo, el servidor está escuchando conexiones en localhost en el puerto 9000, así que instanciamos al WebSocket de la siguiente manera:

var socket;
function init(){
socket = new WebSocket("ws://localhost:9000")
}
Como se puede observar, el protocolo de conexión es «ws» y no «http».

ATENCIÓN es posible que el navegador os impida usar un websocket sin seguridad (ws en lugar de wss) si estáis dentro de una página segura (https), ya que, por norma general, no se permite «bajar» el nivel de seguridad (la seguridad en conjunto es tan fuerte como cada uno de los eslabones).

2.- Asignamos los EventListeners:

function init(){
...
socket.onopen = function(msg) {
alert("Welcome - status "+this.readyState);
};
socket.onmessage = function(msg) {
alert("Received: "+msg.data);
};
socket.onclose = function(msg) {
alert("Disconnected - status "+this.readyState);
};
}
3.- Crear una función para mandar el mensaje:

function send(msg){
if(msg.length > 0) {
socket.send(msg);
}
}
4.- Crear una función para desconectarse:

function quit(){ socket.close(); }
5.- Y otra función para reconectar:

function reconnect(){ quit(); init();}
Y eso es todo. Este trozo del código sí que es público y por tanto tiene que estar en un sitio accesible por los usuarios desde internet (en mi caso lo almaceno en C:\xampp\htdocs\sala_chat\client.html).

Para comprobar su funcionamiento sencillamente debes abrir dos pestañas con el cliente de la sala de chat (localhost/sala_chat/client.html).

RESUMEN


Finalmente os dejo un ejemplo para correr en xampp en el siguiente archivo comprimido: ejemplo websockets PHP + java.

¡Websockets achieved!


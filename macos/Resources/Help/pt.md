# Ajuda do Band·je
O Band·je grava conversas no seu Mac e as transforma em texto. Ele fica na barra de menus: a pequena fita cassete no canto superior direito. Tudo acontece no seu Mac.

## Gravar uma conversa {#record}
Pressione ⌃⌥⌘R para começar e ⌃⌥⌘R de novo para parar.

O Band·je grava duas coisas ao mesmo tempo: seu microfone e todo o som que o seu Mac reproduz. Funciona com qualquer app de chamadas, como FaceTime, Zoom, Teams, Meet ou uma ligação telefônica pelo Mac. O Band·je não grava a sua tela.

- Durante a gravação, a fita na barra de menus fica vermelha, os rolos giram e o tempo corre ao lado, em vermelho.
- O seu Mac não entra em repouso enquanto o Band·je grava.
- Na primeira vez, o macOS pede permissão para gravar o áudio do seu Mac. Permita, senão o Band·je só ouve o seu microfone.
- Se o microfone ficar em silêncio por seis segundos, ou se a tampa for fechada enquanto o microfone interno está em uso, o Band·je avisa você e oferece trocar para outro microfone.

Avise as outras pessoas de que você está gravando. Em alguns países, e em uso profissional, a lei exige isso e, às vezes, também é preciso o consentimento delas. Você é responsável por cumprir a lei que se aplica a você. O Band·je lembra você uma vez, antes da primeira gravação.

### Onde ficam as gravações
Cada gravação ganha uma pasta própria em `~/Music/Bandje` (ou na pasta escolhida em [Ajustes](#settings), ou em iCloud Drive › Band·je quando você [sincroniza com o iCloud](#settings)), com o dia e a hora no nome, como `Gravação 6 de nov 14.32`. O seu iPhone dá nome às gravações dele do mesmo jeito. Na pasta ficam:

- o áudio (`.m4a`): você no canal esquerdo, os outros no direito
- a transcrição (`.md`), que pode ser lida em qualquer app de texto ou de Markdown
- os dados brutos (`.json`), com o tempo de cada palavra
- os resumos, como arquivos `.md`

Abra uma gravação na [janela do Band·je](#player). Escolha **Abrir pasta de gravações** no menu para ver os arquivos. Se o Band·je ou o Mac parar de forma inesperada durante uma gravação, o Band·je oferece salvá-la na próxima vez que abrir.

## Transcrições {#transcripts}
Depois que você para de gravar, o Band·je escreve o que foi dito e quem disse.

O menu mostra o progresso. Você pode começar uma nova gravação enquanto o Band·je transcreve. Quando a transcrição fica pronta, aparece uma pequena marca verde na fita na barra de menus, e o menu mostra **Transcrição pronta**: clique para abrir a gravação na janela do Band·je. A marca some depois que você abre o menu.

- O que você diz aparece como **Eu**. O que os outros dizem aparece como **Outro lado**.
- Quando várias pessoas falam do outro lado, o Band·je as distingue: **Falante 1**, **Falante 2** e assim por diante. Dê nomes a elas com [Nomear falantes](#speakers).
- O mesmo vale para várias pessoas em volta do seu Mac, numa reunião em uma mesa: em vez de **Eu**, elas viram **Falante 1**, **Falante 2** e assim por diante.
- O Band·je entende 25 idiomas, entre eles inglês, holandês, alemão, francês, espanhol, italiano, português, polonês, russo e ucraniano. Você não precisa escolher o idioma.

Para o melhor resultado, use fones de ouvido durante uma chamada. Sem eles, o microfone também capta o outro lado pelos alto-falantes. O Band·je filtra a maior parte disso, mas não tudo.

### Transcrever outro arquivo
Escolha **Transcrever arquivo…** para transcrever qualquer arquivo de áudio, como um memo de voz do iPhone. O Band·je copia o áudio para uma pasta própria na sua pasta de gravações e coloca a transcrição ao lado. O original fica onde estava.

## Nomear falantes {#speakers}
Dê aos falantes de uma transcrição os nomes reais deles.

Abra a gravação na [janela do Band·je](#player) e escolha **Nomear falantes…** em **Mais**, ou escolha **Nomear falantes…** no menu: isso abre a gravação atual. Para trabalhar com uma gravação mais antiga pelo menu, escolha antes **Gravações recentes**.

Para cada falante, você vê a fala mais longa dele. Clique no botão de reprodução para ouvir esse trecho, digite um nome e clique em **Salvar**. O Band·je atualiza a transcrição e qualquer resumo feito depois. Deixe um campo vazio para manter o rótulo.

Numa linha telefônica com menu ou música de espera, o Band·je às vezes ouve mais falantes do que havia. Dê o mesmo nome a dois rótulos, ou deixe o extra como está.

## A janela do Band·je {#player}
Todas as suas gravações numa janela: ouvir, acompanhar a leitura, buscar, nomear falantes, resumir e compartilhar.

Escolha **Abrir o Band·je** no menu (⌘O). A janela também abre quando você mesmo abre o Band·je, por exemplo pelo Launchpad ou pelo Spotlight. **Abrir no Band·je** abre a gravação atual. Enquanto a janela está aberta, o Band·je fica no Dock e no ⌘Tab; feche-a e o Band·je volta a ficar só na barra de menus. Ative **Sempre no Dock** em [Ajustes](#settings) para manter o ícone. Na primeira vez, a janela abre sempre, com as permissões, cada uma com o seu botão. Se você fechar a janela, o Band·je fica na barra de menus; encerre o Band·je por esse menu.

- À esquerda: suas gravações por dia, com a hora, a duração e as primeiras palavras da transcrição. A busca encontra títulos e palavras nas transcrições. Embaixo fica **Iniciar gravação**; enquanto você grava, a nova gravação aparece no topo com um ponto vermelho e, ao parar, a janela a abre.
- À direita: a gravação com a fita cassete, a barra de posição e o botão de reprodução (barra de espaço). Clique numa frase para ouvir a partir dali; durante a reprodução, a frase que você está ouvindo fica destacada e a transcrição acompanha. **Buscar na transcrição** (⌘F) encontra palavras.
- Ao lado de **Transcrição** fica a aba **Resumo**. Sem resumo, contém **Resumir**: escolha um modelo, veja [Resumos](#summaries). Cada resumo tem sua própria aba; **Outro resumo** cria outro.
- Ainda sem transcrição (uma gravação do iPhone, por exemplo)? Clique em **Transcrever**.
- **Compartilhar**: **Áudio…**, **Transcrição (.md)…**, **Transcrição em PDF…** ou **Página web com áudio…**: um arquivo com o player, a transcrição, os resumos e o áudio, que funciona em qualquer navegador, também offline. **Página web com áudio, compacta (para e-mail)…** reduz o áudio. A página tem um link para band.je e mais nada.
- No papel: **Imprimir…** (⌘P, ou em **Compartilhar**) imprime a transcrição, igual ao PDF.
- **Mais**: **Nome e cor…** (ou clique no título na fita): o nome e a cor da fita, **Nomear falantes…**, **Mostrar no Finder**, **Apagar…** (vai para o Lixo).
- Você também pode apagar uma gravação pela lista: clique nela com o botão direito e escolha **Apagar…**, ou selecione-a e pressione ⌫. O Band·je pergunta antes.

## Ditado {#dictation}
Pressione ⌃⌥⌘D, fale, e o texto aparece onde está o cursor: num chat, num e-mail, num editor ou no Terminal.

Há duas formas de usar o atalho:

- **Toque** em ⌃⌥⌘D: o Band·je ouve até você pressionar Return, ou ⌃⌥⌘D de novo. O próprio Return não é enviado ao app.
- **Mantenha** ⌃⌥⌘D pressionado: o Band·je ouve enquanto você segura as teclas e cola quando você as solta.

Pressione Esc para cancelar. O ícone na barra de menus fica laranja enquanto o Band·je ouve, com o tempo ao lado. Um ditado pode durar até cinco minutos; nos últimos 30 segundos, o tempo pisca.

### Colar
O texto sempre fica na área de transferência. Para colar por você, o Band·je precisa de permissão para enviar um pressionamento de tecla (⌘V): escolha **Ativar colagem automática…** no menu, ou vá em Ajustes do Sistema > Privacidade e Segurança > Acessibilidade e ative o Band·je. Sem isso, você mesmo cola com ⌘V.

O macOS só informa essa permissão ao Band·je depois que ele reinicia. Acabou de ativar? Escolha **Reiniciar o Band·je para a colagem automática** no menu, ou **Reiniciar o Band·je** em [Ajustes](#settings).

Se você ouvir um som curto em vez da colagem, um campo de senha ou outro app ativou a entrada segura (a Entrada Segura de Teclado do Terminal, um gerenciador de senhas). O macOS então bloqueia a colagem; o texto está na área de transferência, então pressione ⌘V você mesmo.

Nada do que você dita é salvo.

## Resumos {#summaries}
O Band·je pode resumir uma conversa no formato que você escolher, com a Apple Intelligence no seu Mac.

Os resumos exigem macOS 26 ou posterior, com a Apple Intelligence ativada. Sem ela, o menu **Resumir** não aparece e o Band·je funciona normalmente.

1. Escolha **Resumir** no menu.
2. Em **Escolha um modelo**, escolha um. O Band·je resume a gravação atual. Para resumir outra, escolha-a antes em **Gravações recentes**.
3. Enquanto o Band·je trabalha, brilhos roxos aparecem na barra de menus. Aponte para eles para ver o progresso.
4. Quando termina, aparece uma pequena marca verde na fita e o menu diz **Resumo pronto**. Se a janela do Band·je estiver aberta, ela mostra a gravação.

Você também pode começar na [janela do Band·je](#player): escolha **Resumir** ao lado das abas e selecione um modelo.

O resumo é salvo ao lado da transcrição como `<nome> resumo <modelo>.md`. Um resumo leva de alguns segundos a cerca de um minuto. Conversas longas são resumidas em partes.

O resumo é escrito no idioma da conversa. A Apple Intelligence resume em inglês, holandês, alemão, francês, espanhol, italiano, português e alguns outros idiomas, mas ainda não em polonês, russo ou ucraniano.

O modelo no seu Mac é pequeno. Ele se atém ao que foi dito, mas pode deixar passar detalhes. Confira fatos importantes na transcrição.

O Band·je vem com quatro modelos: uma reunião, uma entrevista de emprego, uma entrevista com cliente e um resumo geral. Para criar o seu, veja [Criar um modelo](#templates).

## Criar um modelo {#templates}
Crie o seu próprio modelo de resumo: um arquivo de texto com os títulos que você quiser.

Um modelo é um arquivo de texto simples (`.md` ou `.txt`) em `~/Music/Bandje/Templates`. O nome do arquivo vira o nome no menu **Resumir**.

O jeito mais rápido: com a janela do Band·je aberta, escolha **Resumir** > **Novo modelo** na barra de menus. O Band·je cria um modelo novo com dois títulos e o abre; altere, salve e dê a ele um nome próprio no Finder.

### Comece por uma cópia
O jeito mais fácil é copiar um exemplo e alterá-lo:

1. Escolha **Resumir** > **Abrir pasta de modelos**.
2. Selecione o exemplo mais parecido com o que você quer, como `Meeting.md`.
3. Escolha Arquivo > Duplicar (⌘D) no Finder e renomeie a cópia, por exemplo `Reunião semanal.md`.
4. Abra a cópia no TextEdit ou em outro app de texto, altere os títulos e salve.

O novo modelo aparece no menu **Resumir** na hora. Você também pode alterar os próprios exemplos ou apagá-los: o Band·je só os recoloca se você apagar a pasta Templates inteira.

### O que vai num modelo
Uma lista de títulos, cada um com uma linha sobre o que vai embaixo dele:

- `## Decisões` com a linha "Cada decisão como um item. Diga quem decidiu."
- `## Ações` com a linha "Quem, o quê e quando."

Dicas:

- Seja específico. "Pretensão salarial com os valores exatos" funciona melhor que "Salário".
- Fique em cerca de cinco títulos. O modelo no seu Mac é pequeno: menos títulos dão respostas melhores.
- Escreva "se isso foi dito" quando algo talvez não apareça, para o Band·je não inventar.
- Os títulos ficam como você os escreve. O texto segue o idioma da conversa.

## Microfone e som {#devices}
Escolha qual microfone usar e para onde vai o som do Mac, direto no menu.

### Microfone
O menu **Microfone** lista todos os microfones. O que está em uso tem uma marca de seleção, e o nome dele aparece abaixo do item de menu. Escolher um muda o microfone do Mac inteiro, então o app de chamadas usa o mesmo. Com a tampa fechada, o microfone interno fica desligado; o Band·je indica isso.

### Saída de som
O menu **Saída de som** lista todos os dispositivos que podem reproduzir som e define a saída de som do Mac. O Band·je nunca a altera sozinho.

Alguns microfones USB têm entrada para fone de ouvido e também contam como alto-falantes. Quando os AirPods se desconectam, o macOS pode mandar o som para lá. Escolha seus alto-falantes em Saída de som para resolver.

## Ajustes {#settings}
Atalhos, a pasta de gravações, permissões, abrir ao iniciar sessão e o idioma do Band·je.

Escolha **Ajustes…** no menu.

### Geral
Ative **Abrir o Band·je ao iniciar sessão** e o Band·je aparece sozinho na barra de menus depois que você inicia sessão. **Sempre no Dock** mantém o Band·je no Dock, também sem a janela. Você também pode escolher isso na janela de boas-vindas, na primeira vez que abre o Band·je. Fica desativado até você ativar. Se você desativar em Ajustes do Sistema > Geral > Itens de Início de Sessão e Extensões, o Band·je mostra isso aqui. Desative **Mostrar a janela do Band·je ao iniciar** e o Band·je fica na barra de menus ao iniciar.

O Band·je segue o idioma do macOS. Para usar outro idioma só no Band·je, escolha-o aqui e clique em **Reiniciar o Band·je**. Menus, janelas, novas transcrições e a Ajuda mudam. **Igual ao macOS** volta ao padrão.

### Atalhos de teclado
Clique num campo e pressione a nova combinação. Ela precisa incluir ⌘, ⌃ ou ⌥, ou ser uma tecla de função. Esc cancela; **Restaurar padrões** traz de volta ⌃⌥⌘R e ⌃⌥⌘D.

Se outro app já usa a combinação, o Band·je avisa e mantém a anterior.

### Som
Escolha o **Microfone** e a **Saída de som**, como no menu do Band·je. Vale para todos os apps, também para ligações.

### Transcrição
**Transcrever automaticamente** transcreve cada gravação assim que você para. **Reconhecer falantes** distingue várias vozes (Falante 1, Falante 2…); desativado, você só recebe Eu e Outro lado. O Band·je reconhece o idioma sozinho.

### Armazenamento
Ative **Sincronizar com o iCloud** e suas gravações, transcrições, resumos e modelos ficam em iCloud Drive › Band·je, no seu iPhone e nos seus outros Macs com a mesma Conta Apple. Uma gravação é feita primeiro no Mac e vai para o iCloud quando você para. O Band·je pergunta se deve mover junto as gravações existentes. Desative e a sua própria pasta volta a ser a pasta de gravações; nada é apagado do iCloud, e o Band·je oferece copiar as gravações de volta. A Apple criptografa o iCloud Drive de ponta a ponta quando a Proteção Avançada de Dados está ativada.

Clique em **Alterar…** e escolha uma pasta, em qualquer lugar do Mac ou num disco externo. As novas gravações e os arquivos transcritos vão para lá. As gravações existentes ficam onde estão, assim como seus modelos e os modelos de fala. **Usar ~/Music/Bandje** volta para a pasta padrão.

Se a pasta estiver no iCloud Drive, no Dropbox ou em outro serviço de nuvem (também Mesa e Documentos quando estão no iCloud), o Band·je avisa: suas gravações então saem do Mac por esse serviço.

### Acesso
Se o Band·je pode usar o microfone, colar para você e gravar o som do seu Mac, cada um com seu botão (**Permitir…** ou **Abrir ajustes…**). Uma marca verde significa permitido; o estado se atualiza sozinho quando você volta dos Ajustes do Sistema. Veja [Solução de problemas](#troubleshooting).

## Privacidade e rede {#privacy}
Seu áudio, suas transcrições e seus resumos nunca saem do seu Mac.

- Sem conta, sem análises, sem rastreamento. Nenhum servidor nosso.
- iCloud só se você ativar [Sincronizar com o iCloud](#settings): aí suas gravações ficam no seu próprio iCloud Drive, como seus outros arquivos. O Band·je nunca as vê.
- Tudo fica na sua pasta de gravações: `~/Music/Bandje`, a menos que você tenha escolhido outra. Apague uma pasta e ela some. Se você escolher uma pasta no iCloud Drive ou em outro serviço de nuvem, suas gravações vão para esse serviço; o Band·je avisa antes.
- A transcrição, o reconhecimento de falantes e o ditado acontecem no seu Mac.
- Os resumos usam apenas o modelo da Apple Intelligence no seu Mac, nunca o Private Cloud Compute da Apple.

O mecanismo de fala da Desert Ant Labs verifica a licença pela rede: no máximo uma vez por mês por modelo de fala. Ele envia um ID de instalação aleatório, o modelo, a versão do mecanismo e o ID do app. Nunca áudio, nunca texto. **Sobre o Band·je** também mostra isso.

## Memória e armazenamento {#resources}
O Band·je é leve: cerca de 60 a 70 MB de memória enquanto está aberto.

Os modelos de fala vêm com o Band·je: cerca de 400 MB do tamanho do app. O Band·je nunca baixa nada por conta própria.

Alguns segundos depois de abrir, o Band·je carrega o modelo de fala em segundo plano, para o ditado ficar pronto na hora. Na primeiríssima vez num Mac, isso leva cerca de 20 segundos, porque o macOS otimiza o modelo para o seu chip. Depois disso é rápido.

Uma hora de áudio ocupa cerca de 55 MB. Transcrevê-la exige um pouco mais de memória enquanto acontece.

## Solução de problemas {#troubleshooting}
Soluções para o que pode dar errado.

### Verifique primeiro as permissões
Muitos problemas vêm de uma permissão que falta. Escolha **Ajustes…** e veja em **Acesso**:

- **Microfone**: necessário para gravar sua voz e para ditar.
- **Som do Mac**: necessário para gravar o outro lado. O macOS não deixa os apps lerem essa permissão, então o Band·je mostra o que aconteceu na última gravação: chegou som, ou ficou em silêncio. Silêncio é normal se nada estava tocando.
- **Colagem automática**: necessária para colar o texto ditado por você.

Uma marca verde significa permitido. Senão, clique em **Abrir ajustes…**, ative o Band·je e volte; o Band·je percebe sozinho.

Sempre que abre, o Band·je verifica o microfone e a colagem automática, e avisa se faltar algum. Não precisa da colagem automática? Marque **Não mostrar esta mensagem novamente**, ou desative **Avisar ao iniciar se faltar algo** em Acesso.

### O outro lado não aparece na gravação
O macOS não permitiu que o Band·je gravasse o áudio do Mac. Vá em Ajustes do Sistema > Privacidade e Segurança > Gravação do Áudio do Sistema e da Tela e ative o Band·je em Apenas Gravação do Áudio do Sistema.

### Minha própria voz não aparece
Verifique o menu **Microfone**. Com a tampa fechada, o microfone interno fica desligado: escolha outro. Se o Band·je não tiver permissão para usar o microfone, ative-a em Ajustes do Sistema > Privacidade e Segurança > Microfone.

### Não ouço nada depois de tirar os AirPods
O macOS mandou o som para outro dispositivo, como um microfone USB com entrada para fone de ouvido. Escolha seus alto-falantes em **Saída de som**.

### A transcrição não faz sentido
Provavelmente a conversa está num idioma que o Band·je não conhece. O Band·je não tem como saber, então escreve o que acha que ouviu.

### Há mais falantes do que havia
Menus telefônicos, música de espera e linhas ruins podem confundir o reconhecimento de falantes. Dê os nomes certos aos rótulos em [Nomear falantes](#speakers).

### Resumir não aparece no menu
Os resumos exigem macOS 26 ou posterior, com a Apple Intelligence ativada em Ajustes do Sistema > Apple Intelligence e Siri. O idioma do Mac e o idioma da Siri precisam ser iguais.

### O atalho não funciona
Outro app pode estar usando a mesma combinação. Escolha outra em [Ajustes](#settings).

## Sobre o Band·je {#about}
O Band·je é feito pela Neurendal B.V., na Holanda.

Reconhecimento de fala e de falantes: Voz e Who, da Desert Ant Labs, baseados em NVIDIA Parakeet TDT 0.6B v3 e pyannote community-1 (CC BY 4.0). Resumos: Apple Intelligence.

Escolha **Sobre o Band·je** no menu para ver as versões e os links.

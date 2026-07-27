# Unarmored Dodge

Mod dla OpenMW (Lua-only) nadający umiejętności **Unarmored** drugą oś wartości: skalowany
efekt **Sanctuary**, czyli realny unik, zamiast samego armor rating.

To repozytorium jest **źródłem prawdy** moda i jednocześnie katalogiem montowanym przez grę
(`data=`), więc nie ma tu kopii, które mogłyby się rozjechać.

## Problem

Waniliowe Unarmored daje `0,0065 × skill²` armor rating na slot — przy skillu 30 to 5,85,
więc przez pierwsze ~60 poziomów umiejętności praktycznie nic, i nigdy nic **poza** AR.

Klasyczna „naprawa" przez podniesienie GMST `fUnarmoredBase1/2` ma udokumentowany efekt
uboczny: NPC przestają zakładać słaby pancerz. To **nie** jest artefakt MCP — silnik robi to
sam, w `mwworld/inventorystore.cpp` (`autoEquipArmor`), odrzucając każdą sztukę pancerza
gorszą od `unarmoredRating` liczonego właśnie z tych GMST-ów.

Ten mod **nie dotyka żadnego GMST-a**, więc problem nie występuje.

## Co robi

Umiejętność Unarmored przelicza się na punkty Sanctuary. W silniku 1 pkt Sanctuary = 1 punkt
procentowy mniejszej szansy trafienia (`defenseTerm` w `mwmechanics/combat.cpp`), więc bonus
działa na ciosy wręcz i pociski, a **nie** na czary — dokładnie jak w wanilii.

Pancerz **nie wyłącza** bonusu, tylko go tnie: każdy slot liczy się własnym skillem
(Light/Medium/Heavy Armor) z konfigurowalnym udziałem. Unarmored **uzupełnia** pozostałe
umiejętności pancerza zamiast z nimi konkurować.

**Unik zawsze pochodzi z Unarmored.** Umiejętności pancerza nigdy go nie generują — mogą
wyłącznie modulować to, co Unarmored już dało. Postać bez wytrenowanego Unarmored nie unika,
choćby miała Heavy Armor 100.

Przełącznik **`Armour proficiency matters`** decyduje, czy biegłość w noszonym pancerzu
dodatkowo skaluje wynik:

| Przypadek (przy domyślnym `keepLight` 60 %) | ON (domyślnie) | OFF |
|---|---|---|
| Unarmored 100, pełny lekki, Light Armor 100 | 19 pkt | 19 pkt |
| Unarmored 100, pełny lekki, Light Armor 50 | **10 pkt** | **19 pkt** |
| Unarmored 7, pełny średni, Medium Armor 64 | **0 pkt** | **0 pkt** |

Wzór dla slotu: `waga × keep% × biegłość × dodgeZeSkilla(unarmored)`, gdzie biegłość to
`skill_pancerza / 100` przy ON (obcięte do 1,0) albo 1,0 przy OFF. Pusty slot ma biegłość 1,0
i pełne `keep`.

Bonus dostają też NPC (osobny współczynnik, domyślnie 50 %). Efekt jest pasywny, więc
z natury działa również w starciach NPC kontra NPC. Stwory są poza modem — patrz „Architektura".

## Wymagania

- **OpenMW ≥ 0.51** — mod używa interfejsu `I.Combat` (`getArmorSkill`, `addOnHitHandler`,
  `getArmorRating`), który wszedł wraz z przeniesieniem mechanik walki do Lua
  (commit `e978c230dc`, przodek tagu `openmw-51-rc1`).
- Brak twardych zależności od innych modów.

## Integracje (opcjonalne, wykrywane w runtime)

| Mod | Co daje |
|---|---|
| **Stats Window Extender** | linia „Dodge" w oknie postaci + tooltip z rozbiciem wkładu per slot |
| **Inventory Extender** | bonus obok armor rating na pasku informacyjnym ekwipunku |
| **Skill Evolution** | progresja za unik idzie przez `I.SkillProgression.skillUsed`, więc tempo dalej ustawia SE |

Brak któregokolwiek z nich = mod działa normalnie, bez błędu w logu.

### Zweryfikowana zgodność

| Co sprawdzone | Wynik |
|---|---|
| Inne nadpisania `I.Combat` | **brak** — jesteśmy jedynym modem z `interfaceName = 'Combat'` |
| Inne zapisy do Sanctuary | **brak** |
| Nadpisania GMST `fUnarmoredBase1/2` | **brak** |
| **Skill Evolution** | zgodne. Nasze `skillUsed` przechodzi przez 9 handlerów SE, więc jego mnożniki (`Armor_HitByOpponent`, gain 1,25) nakładają się na naszą skalę. SE czyta też Sanctuary w swojej rekonstrukcji szansy trafienia, więc nasz bonus widzi automatycznie |
| **Natural Character Growth** | zgodne, ale **nie neutralne** — patrz niżej |

⚠ **NCG zmienia wagę opcji `dodgeXpScale`.** NCG rozwija atrybuty z przyrostu umiejętności
(`core/attributes.lua`, `getGrowth`), a Unarmored mapuje na **speed 3, agility 2, endurance 1,
personality 1**. Czyli progresja za unik nie kończy się na samym skillu — napędza też atrybuty
i, przez major/minor, postęp poziomu. Dodatkowo Agility wchodzi do waniliowego `defenseTerm`,
więc powstaje łagodna pętla dodatnia: więcej uników → szybszy Unarmored → więcej Agility →
znów lepszy unik. Nie jest to runaway, ale przy strojeniu `dodgeXpScale` warto o tym pamiętać.

⚠ **`dodgeXpScale = 0` nie może wysłać zdarzenia.** SE na `scale <= 0` robi `return false`
(`skills/handlers.lua:242-244`), a `false` z handlera **zatrzymuje resztę łańcucha**
(`openmw_aux/util.lua:119-128`).

Co ginie: handlery lecą w **odwrotnej kolejności rejestracji**, a SE rejestruje swoje jako
`final, external, levelScaled, decay, magic, scaled, uses, capper, scale` — więc `scale` leci
pierwszy, a `final` ostatni. `false` z `scale` wycina **całą resztę pipeline'u SE**, w tym
`final`, czyli jedyny handler faktycznie naliczający przyrost (`handlers.lua:87-96`).
Efekt: zero nauki plus linia `print` w logu przy **każdym** uniku.

Czego **nie** ginie (sprostowanie wcześniejszego szacunku): mody rejestrujące się wprost
w `I.SkillProgression` ładują się w tej instalacji **po** SE (Reading is Good, Disenchanting,
Toxicology, Bullseye, Fair Trade), więc w odwrotnej iteracji biegną *przed* handlerem `scale`
i są nietknięte. Ucierpiałby tylko mod podpięty przez własne API SE (`addSkillUsedHandler`) —
a takiego tu nie ma; HBFS i N'Garde używają `addOnHitHandler`, czyli innego łańcucha.

Zero traktujemy więc jak wyłączoną opcję i zdarzenia nie wysyłamy w ogóle.

## Instalacja

Lua-only, więc **bez regenu** `momw-configurator`:

1. `data="…/UnarmoredDodge"` — katalog z tego repozytorium (append),
2. `content=unarmored-dodge.omwscripts` (insert **przed** `delta-merged.omwaddon`),
3. jedno i drugie w `momw-customizations-ev.toml` **oraz** ręcznie w `openmw.cfg`
   (przy zamkniętym launcherze).

Kolejność w load order jest obojętna — mod nie zależy od żadnego innego `.omwscripts`.

## Konfiguracja

Options → Scripts → **Unarmored Dodge**, trzy grupy: **Balance**, **Armour coverage**
i **Update frequency**. Nic nie jest zaszyte w kodzie — `formula.lua` czyta wyłącznie to,
co przyjdzie z konfiguracji. Zmiana działa od razu, bez restartu (gracz), NPC dociągają
w ciągu ~10 s.

Wartości domyślne (wystrojone w grze, nie wzięte z sufitu):

| | | | |
|---|---|---|---|
| cap **40** | próg **20** | punkty na poziom **0,4** | udział NPC **100 %** |
| lekki **60 %** | średni **40 %** | ciężki **20 %** | biegłość pancerza **ON** |
| mnożnik AR **1,00x** | nauka za unik **0,5** | | |

Przy tym zestawie goły Unarmored 100 daje **32 punkty**. Punkt odniesienia: mody inspiracyjne
(#51332, #55758) kończą w okolicach 40–60 przy skillu 100.

## Architektura

```
scripts/unarmored_dodge/
  config.lua       wartości + definicje 3 grup ustawień (globalne sekcje storage,
                   żeby czytały je także skrypty NPC; mapa klucz->sekcja wyprowadzana
                   z definicji, więc nie da się jej rozjechać)
  formula.lua      czysta funkcja: (ekwipunek, skille) -> Sanctuary + składowa AR.
                   ⚠ ZERO zależności od pakietów silnika — sloty mają własne klucze
                   tekstowe, bo skrypty MENU nie dostają `openmw.types` i inaczej
                   nie dałoby się liczyć podglądów w ustawieniach
  slider.lua       MENU   — własny renderer suwaka
  menu.lua         MENU   — rejestracja strony opcji (globalny interfejs Settings
                            wystawia tylko registerGroup)
  global.lua       GLOBAL — grupy ustawień + leniwa fabryka rekordów zaklęć
  actor.lua        NPC,PLAYER — przeliczanie i nakładanie zdolności
  armor.lua        NPC,PLAYER — opcjonalny override I.Combat.getArmorRating
  player.lua       PLAYER — progresja Unarmored za unik
  statswindow.lua  PLAYER — integracja ze Stats Window Extender
```

**Stwory są celowo poza modem** — nie mają realnej umiejętności Unarmored (silnik wyprowadza
ich wartość ze specjalizacji) i nie dostają z niej waniliowego armor rating, więc nie ma czego
skalować. Brak `CREATURE` w rejestracji = zero kosztu na każdym stworze w świecie.

### Suwaki

Silnik ma tylko `textLine`, `checkbox`, `number`, `select` i `color` — suwaka nie ma.
`slider.lua` rejestruje własny renderer w kontekście MENU. Sun's Dusk wozi współdzielony
`SuperSlider4`, ale **nie robimy z niego zależności**: brakujący renderer psuje całą stronę
ustawień (objaw „unknown renderer", ten sam, który wyłożył Quest Markers Plus).

Suwaki dostały wszystkie wartości balansu. Interwały odświeżania **zostały polami liczbowymi** —
zakres 0,1–300 s jest za szeroki na suwak, a te wartości ustawia się raz i chce się wpisać
konkret, nie trafiać w krok.

### Interaktywne podglądy

Pod suwakami balansu leci linijka z **policzonym na żywo przykładem** (np. „Full light armour,
skills 100 → 13 pts"), zamiast statycznego tekstu w opisie. Działa, bo zapis wartości
przerysowuje całą grupę ustawień (`menu.lua:361-371`), więc renderer liczy przykład od nowa
przy każdym ruchu suwaka.

Dwa ograniczenia, które ukształtowały to rozwiązanie:
- **`argument` ustawienia trafia do storage**, więc nie może zawierać funkcji. Scenariusz
  podglądu wskazujemy kluczem tekstowym, a funkcje trzyma `slider.lua`.
- **Skrypty MENU nie dostają `openmw.types`** (`luabindings.cpp`, `initMenuPackages`), stąd
  `formula.lua` bez zależności od silnika.

Podglądy używają **tej samej ścieżki kodu co gra** (`formula.preview`), a testy sprawdzają,
że scenariusz podglądu daje ten sam wynik co zwykłe wyliczenie na tym samym układzie.

### Kiedy bonus jest przeliczany

Nigdy co klatkę — `onUpdate` tylko porównuje znaczniki czasu.

⚠ **Odmierzamy czas RZECZYWISTY (`core.getRealTime()`), nie `dt`.** Ekwipunek zmienia się przy
otwartym oknie, a ono **pauzuje grę** — `onUpdate` dostaje wtedy `dt = 0`, więc throttle oparty
na `dt` stawałby dokładnie w momencie, w którym jest potrzebny. Objaw: wartość na pasku
Inventory Extender nie drgała, dopóki nie zamknęło się ekwipunku.

| Wyzwalacz | Gracz | NPC |
|---|---|---|
| Pełne przeliczenie — **konfigurowalne** | 1 s | 10 s |
| Kontrola ekwipunku — **wyprowadzana** jako ⅕ powyższego | 0,2 s | 2 s |
| `onInit`, `onActive` (wejście w aktywną strefę, wczytanie sejwa) | zawsze | zawsze |
| Zmiana ustawienia | natychmiast (gracz) | przy najbliższym przeliczeniu |

Interwał kontroli ekwipunku **nie jest ustawieniem**. Rozdzielenie go od pełnego przeliczenia
ma sens dopiero przy długim `refreshInterval`; przy domyślnej sekundzie kupowałoby 0,8 s
responsywności kosztem dwóch suwaków i konieczności rozumienia różnicy między dwoma rodzajami
odświeżania.

**`Periodic updates for NPCs` = off** wyłącza dla NPC oba interwały: zostają wyłącznie `onInit`
i `onActive`, czyli **zero pracy na klatkę** w tłocznych lokacjach. Skille NPC są statyczne,
więc traci się tylko reakcję na pancerz zmieniany w trakcie walki.

Interwały nie są czytane ze storage co klatkę — to kosztowałoby więcej niż praca, którą
ograniczają. Siedzą w cache'u odświeżanym przy każdym pełnym przeliczeniu, a u gracza
dodatkowo natychmiast po zmianie suwaka (subskrypcja wszystkich trzech sekcji).

Silnik **nie ma** handlera na założenie/zdjęcie przedmiotu — lista `EngineHandlerList`
w `localscripts.hpp` to `onActive` / `onInactive` / `onConsume` / `onActivated` /
`onTeleported` i nic więcej. Stąd polling, ale tani: jedno `getEquipment` i sklejenie
9 identyfikatorów w podpis. Pełne przeliczenie odpala się dopiero, gdy podpis się zmieni,
a nakładanie zdolności — dopiero gdy zmieni się sama liczba punktów.

### Dlaczego zaklęcia, a nie `activeEffects:modify()`

`modify()` zapisuje **trwałą** zmianę magnitudy do sejwa i wymaga własnej księgowości
w `onSave`/`onLoad`. Dokładnie tak powstał runaway Strength w Slay's Assassin Mark: `onSave`
zapisywał zero, modyfikator kumulował się bez końca. Zdolność (ability) usuwa efekt razem
ze sobą i nie wymaga żadnej księgowości — zostaje tylko zapamiętanie, która jest nałożona,
żeby po wczytaniu sejwa nie dołożyć drugiej.

Rekordy zaklęć powstają w runtime przez `world.createRecord`, po jednym na możliwą magnitudę.
Żadnego ESP-a, żadnego regenu.

## Odinstalowanie

Rekordy utworzone w runtime zostają w sejwie, więc **zdejmij zdolność przed usunięciem moda**:
ustaw `Maximum Sanctuary` na `0`, poczekaj chwilę (gracz odświeża się co sekundę), zapisz grę,
dopiero potem usuń `data=` i `content=`.

## Sprawdzanie w grze

⚠ **Konsola sama dokleja `return`** (`omw/console/local.lua`, `util.loadCode('return ' .. code)`).
Własne `return` daje `return return ...`, czyli błąd składni — wtedy konsola po cichu wykonuje
kod ścieżką zapasową i **wyrzuca wynik**. Objaw: brak jakiegokolwiek wypisu, nawet błędu.
Wpisuj samo wyrażenie. `require` też jest zbędne — środowisko konsoli ma już `I`, `types`,
`self`, `core` i `view` jako globalne.

**Gracz** — konsola, `luap`:

```
I.UnarmoredDodge.getBonus()
types.Actor.activeEffects(self):getEffect('sanctuary').magnitude
view(I.UnarmoredDodge.getBreakdown(), 3)
```

**NPC** — kliknij go w konsoli, potem `luas` (kontekst lokalny na zaznaczonym obiekcie).
Te same polecenia działają: `openmw.interfaces` to jedna tabela na obiekt współdzielona przez
wszystkie jego skrypty (`components/lua/scriptscontainer.cpp:44-45`), więc konsolowy skrypt
widzi nasz interfejs. Dodatkowo lista zaklęć potwierdzi nałożoną zdolność:

```
for _, s in pairs(types.Actor.spells(self)) do print(s.id) end
```

**Kogo wybrać:** ubrania **nie są pancerzem**, więc NPC w samych szatach ma wszystkie 9 slotów
gołych i dostaje pełny bonus — mag, mieszczanin, żebrak. Opancerzony NPC da zero i niczego nie
dowiedzie. Na czas testu warto podnieść `NPC share` do 100% i zbić `Skill threshold` do 0.

⚠ Przy teście bojowym bij cel **świadomy i stojący**: Sanctuary jest całkowicie pomijane, gdy
ofiara leży, jest sparaliżowana albo nieświadoma (cios ze skradania).

## Testy

`formula.lua` jest czystą funkcją i da się go sprawdzić poza grą:

```bash
cd tests && python runtest.py
```

Wymaga `lupa` (prawdziwy interpreter Lua w Pythonie). Bez żadnych stubów — `formula.lua`
nie ma zależności od silnika, więc wykonywany jest **oryginalny** plik moda. 22 przypadki:
krzywa, komplety pancerza, pojedyncze sloty, `useArmorSkill` w obu trybach, scenariusze
podglądów i zgodność podglądu ze zwykłym wyliczeniem.

Drugi walidator sprawdza l10n wobec definicji ustawień:

```bash
cd tests && python check_l10n.py
```

Wymaga `pyyaml`. Pilnuje czterech rzeczy, z których każda już raz coś złapała: poprawności
YAML-a (nieocytowany dwukropek w opisie wywala **cały** plik, a z nim stronę opcji), kompletu
kluczy dla ustawień i grup, braku kluczy osieroconych, oraz składni placeholderów —
ICU używa `{name}`, a `%{name}` renderuje się dosłownie jako `%32`.

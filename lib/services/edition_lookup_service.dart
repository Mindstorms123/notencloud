/// Provides publisher, arranger, original instrumentation notes,
/// and online search links for sheet music in the Blasorchester repertoire.
class EditionInfo {
  final String title;
  final String publisher;
  final String arranger;
  final String series;
  final String? directUrl;
  final String instrumentationNote;
  final List<String> naturallyMissingInstruments; // Instruments never included in this edition

  const EditionInfo({
    required this.title,
    this.publisher = '',
    this.arranger = '',
    this.series = '',
    this.directUrl,
    this.instrumentationNote = '',
    this.naturallyMissingInstruments = const [],
  });
}

class EditionLookupService {
  /// Known verified sheet music editions for pieces in the repertoire
  static final Map<String, EditionInfo> _catalog = {
    // --- 00_Noten Upload (Hal Leonard / Young Concert Band / Discovery Series) ---
    'aladdin': const EditionInfo(
      title: 'Aladdin',
      publisher: 'Hal Leonard',
      arranger: 'John Moss / Michael Sweeney',
      series: 'Discovery Plus / Young Concert Band',
      instrumentationNote: 'Original-Besetzung: Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, F-Horn (1 Part), Posaune, Bariton, Tuba, Percussion. Kein Flügelhorn, kein Horn 2-4 im Original.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'avengers endgame': const EditionInfo(
      title: 'Avengers Endgame',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band (Grade 3)',
      instrumentationNote: 'Originalfassung Hal Leonard: Flöte, Oboe, Fagott, Klarinetten 1-3, Bassklarinette, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, Horn in F, Posaunen 1-2, Bariton/Euphonium, Tuba, Percussion 1-2, Mallets, Pauken. Kein deutsches Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'beauty and the beast (medley)': const EditionInfo(
      title: 'Beauty and the Beast (Medley)',
      publisher: 'Hal Leonard',
      arranger: 'Michael Sweeney',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Young Band Arrangement: Flöte, Klarinetten 1-2, Altsax 1-2, Tenorsax, Trompeten 1-2, F-Horn, Posaune/Bariton, Tuba, Drums. Ohne Flügelhorn und ohne Horn 2.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'hans zimmer movie milestones': const EditionInfo(
      title: 'Hans Zimmer Movie Milestones',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Hal Leonard Concert Band: Flöte, Oboe, Fagott, Klarinette 1-3, Basskl., Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, Horn in F, Posaune 1-2, Bariton, Tuba, Percussion. Kein Flügelhorn im Verlagssatz.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'happy (from despicable me 2)': const EditionInfo(
      title: 'Happy (from Despicable Me 2)',
      publisher: 'Hal Leonard',
      arranger: 'Michael Sweeney',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Hal Leonard Pop-Serie: Flöte, Klarinette 1-2, Altsax 1-2, Tenorsax, Trompete 1-2, F-Horn, Posaune, Bariton, Tuba, Percussion. Kein Flügelhorn im Original.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'highlights from disney\'s frozen 2': const EditionInfo(
      title: 'Highlights from Disney\'s Frozen 2',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Hal Leonard Young Concert Band: Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Trompeten 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Percussion. Kein Flügelhorn, Horn 1-stimmig.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'highlights from la la land': const EditionInfo(
      title: 'Highlights from La La Land',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Enthält "Another Day of Sun", "City of Stars", "Mia & Sebastian\'s Theme". Flöte, Oboe, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, Horn, Posaune 1-2, Bariton, Tuba, Percussion. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'highlights from the jungle book': const EditionInfo(
      title: 'Highlights from The Jungle Book',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, Horn in F, Posaune, Bariton, Tuba, Percussion. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'highlights from willy wonka & the chocolate factory': const EditionInfo(
      title: 'Highlights from Willy Wonka & The Chocolate Factory',
      publisher: 'Hal Leonard',
      arranger: 'Robert Longfield',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Discovery Plus Arrangement: Flöte, Klarinetten 1-2, Altsax 1-2, Tenorsax, Trompete 1-2, F-Horn, Posaune, Bariton, Tuba, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'i\'m still standing': const EditionInfo(
      title: 'I\'m Still Standing',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Elton John Hit für Blasorchester: Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, Horn in F, Posaune 1-2, Bariton, Tuba, Drums.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'john williams in concert': const EditionInfo(
      title: 'John Williams in Concert',
      publisher: 'Hal Leonard',
      arranger: 'Paul Lavender',
      series: 'Concert Band',
      instrumentationNote: 'Gefeierte Williams-Medley: Flöte, Oboe, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Tuba, Pauken, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'michael jackson through the years': const EditionInfo(
      title: 'Michael Jackson Through The Years',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Medley: Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Drums. Ohne Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'moana': const EditionInfo(
      title: 'Moana',
      publisher: 'Hal Leonard',
      arranger: 'Johnnie Vinson',
      series: 'Discovery Plus / Flex-Band',
      instrumentationNote: 'Flex-Band / Discovery Band: 5 flexible Hauptstimmen + Percussion.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'pixar movie magic': const EditionInfo(
      title: 'Pixar Movie Magic',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, F-Horn, Posaunen 1-2, Bariton, Tuba, Mallets, Drums. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'remember me (from coco)': const EditionInfo(
      title: 'Remember Me (from Coco)',
      publisher: 'Hal Leonard',
      arranger: 'Johnnie Vinson',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Flöte, Klarinette 1-2, Altsax 1-2, Tenorsax, Trompete 1-2, Horn, Posaune, Bariton, Tuba, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'selections from incredibles 2': const EditionInfo(
      title: 'Selections from Incredibles 2',
      publisher: 'Hal Leonard',
      arranger: 'Paul Murtha',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Schlagwerk.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'singin\' in the rain': const EditionInfo(
      title: 'Singin\' in the Rain',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Drums. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'skyfall': const EditionInfo(
      title: 'Skyfall',
      publisher: 'Hal Leonard',
      arranger: 'Robert Longfield',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Adele Bond-Song: Flöte, Klarinetten 1-2, Altsax 1-2, Tenorsax, Trompeten 1-2, Horn in F, Posaune, Bariton, Tuba, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'soundtrack highlights from spider-man no way home': const EditionInfo(
      title: 'Soundtrack Highlights from Spider-Man No Way Home',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Drums.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),

    // --- 01_Aktuelle Noten ---
    'bella romantica': const EditionInfo(
      title: 'Bella Romantica',
      publisher: 'Rundel',
      arranger: 'Kurt Gäble',
      series: 'Rundel Blasorchester',
      instrumentationNote: 'Polka von Kurt Gäble: Vollständige deutsche Blasorchester-Besetzung mit Direktion/Partitur, Flöte 1-2, Oboe, Fagott, Klarinetten 1-3, Saxophone, Flügelhörner 1-2, Tenorhorn 1-3, Bariton, Trompeten 1-2, Hörner 1-4, Posaunen 1-3, Bässe 1-2, Schlagzeug.',
      naturallyMissingInstruments: [],
    ),
    'around the whiskey jar': const EditionInfo(
      title: 'Around The Whiskey Jar',
      publisher: 'De Haske / Hal Leonard',
      arranger: 'Peter Kleine Schaars',
      series: 'De Haske Concert Band',
      instrumentationNote: 'Irische Traditionals für Blasorchester arrangiert. Umfasst Flöten, Oboe, Fagott, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Euphonium, Tuba, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'deep purple medley': const EditionInfo(
      title: 'Deep Purple Medley',
      publisher: 'De Haske / Yamaha',
      arranger: 'Toshihiko Sahashi',
      series: 'New Sounds in Brass',
      instrumentationNote: 'Enthält "Burn", "Highway Star", "Smoke on the Water". Konzertblasorchester-Besetzung mit Flöten, Klarinetten 1-3, Saxophonen, Trompeten 1-4, Hörnern 1-4, Posaunen 1-3, Euphonium, Tuba, E-Bass, Drums, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'don\'t stop believin\'': const EditionInfo(
      title: 'Don\'t Stop Believin\'',
      publisher: 'Hal Leonard',
      arranger: 'Paul Murtha',
      series: 'Young Concert Band',
      instrumentationNote: 'Journey Hit: Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, F-Horn, Posaunen 1-2, Bariton/Euphonium, Tuba, Drums, Keyboard/Gitarre optional. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'choral and rock-out': const EditionInfo(
      title: 'Choral And Rock-Out',
      publisher: 'Molenaar Edition',
      arranger: 'Ted Huggens',
      series: 'Molenaar Original Band Music',
      instrumentationNote: 'Klassiker für Blasorchester von Ted Huggens. Flöte/Piccolo, Oboe, Fagott, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Tuba, Drums, Timpani.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'fairytale of new york': const EditionInfo(
      title: 'Fairytale of New York',
      publisher: 'Hal Leonard',
      arranger: 'Sean O\'Loughlin',
      series: 'Concert Band',
      instrumentationNote: 'Pogues Hit für Blasorchester. Flöten, Klarinetten, Saxophone, Trompeten, Hörner, Posaunen, Bariton, Tuba, Percussion. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'how to train your dragon': const EditionInfo(
      title: 'How to Train Your Dragon',
      publisher: 'Hal Leonard',
      arranger: 'Sean O\'Loughlin',
      series: 'Young Concert Band',
      instrumentationNote: 'Filmmusik John Powell: Flöte, Oboe, Fagott, Klarinetten 1-3, Basskl., Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Pauken, Mallets, Percussion. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'i will survive': const EditionInfo(
      title: 'I Will Survive',
      publisher: 'Bernaerts Music',
      arranger: 'Frank Bernaerts',
      series: 'Bernaerts Pop Series',
      instrumentationNote: 'Gloria Gaynor Disco Classic: Vollständige Concert Band Besetzung inklusive umfangreicher Zusatzstimmen für Fanfare und Harmonie.',
      naturallyMissingInstruments: [],
    ),
    'life on mars': const EditionInfo(
      title: 'Life on Mars',
      publisher: 'Hal Leonard / Bernaerts',
      arranger: 'Frank Bernaerts',
      series: 'Bernaerts Music',
      instrumentationNote: 'David Bowie Hit: Flöten, Klarinetten 1-3, Saxophone, Trompete/Cornet 1-3, Horn 1-4, Posaunen 1-3, Euphonium, Bässe, Drums.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'metal!': const EditionInfo(
      title: 'Metal!',
      publisher: 'Hal Leonard',
      arranger: 'Sean O\'Loughlin',
      series: 'Young Concert Band',
      instrumentationNote: 'Medley (Iron Man, Rock You Like A Hurricane, Master of Puppets): Flöte, Klarinette 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Drums. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'moment for morricone': const EditionInfo(
      title: 'Moment For Morricone',
      publisher: 'De Haske / Hal Leonard',
      arranger: 'Johan de Meij',
      series: 'De Haske Concert Band Series',
      instrumentationNote: 'Legendäres Arrangement von Johan de Meij: Flöte 1-2, Oboe, Fagott, Es-Klarinette, Klarinette 1-3, Basskl., Altsax 1-2, Tenorsax, Barisax, Flügelhörner 1-2, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton/Euphonium, Tuba 1-2, Pauken, Percussion 1-3.',
      naturallyMissingInstruments: [],
    ),
    'music': const EditionInfo(
      title: 'Music',
      publisher: 'Tierolff',
      arranger: 'R. Beck',
      series: 'Tierolff Pop Series',
      instrumentationNote: 'John Miles Hymne: Flöten, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Bässe, Percussion.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'pirates of the caribbean': const EditionInfo(
      title: 'Pirates Of The Caribbean',
      publisher: 'Hal Leonard',
      arranger: 'Michael Sweeney / John Wasson',
      series: 'Young Concert Band',
      instrumentationNote: 'Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, F-Horn, Posaune 1-2, Bariton, Tuba, Pauken, Schlagzeug. Kein Flügelhorn im Notensatz.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'radar love': const EditionInfo(
      title: 'Radar Love',
      publisher: 'De Haske / Golden River Music',
      arranger: 'Roland Smeets',
      series: 'Pop for Band',
      instrumentationNote: 'Golden Earring Rock-Hit: Flöten, Oboe, Fagott, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Tenorhorn/Bariton 1-2, Bässe, E-Bass, Drums.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'september': const EditionInfo(
      title: 'September',
      publisher: 'Hal Leonard',
      arranger: 'Paul Murtha',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Earth Wind & Fire: Flöte, Klarinetten 1-2, Altsax 1-2, Tenorsax, Trompeten 1-2, F-Horn (1 Part), Posaune, Bariton, Tuba, Percussion. Kein Flügelhorn, kein Horn 2 im Original.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'spinning wheel': const EditionInfo(
      title: 'Spinning Wheel',
      publisher: 'Hal Leonard',
      arranger: 'Les Taylor',
      series: 'Jazz Band / Concert Band',
      instrumentationNote: 'Blood Sweat & Tears Hit: Flöte, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner, Posaunen, Bariton, Tuba, Drums. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'star wars the force awakens': const EditionInfo(
      title: 'Star Wars The Force Awakens',
      publisher: 'Hal Leonard',
      arranger: 'Michael Brown',
      series: 'Young Concert Band',
      instrumentationNote: 'Filmmusik John Williams: Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-2, Horn in F, Posaune 1-2, Bariton, Tuba, Pauken, Schlagwerk. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'summernight rock': const EditionInfo(
      title: 'Summernight Rock',
      publisher: 'Rundel',
      arranger: 'Steve McMillan / Erwin Jahreis',
      series: 'Rundel Rock & Pop',
      instrumentationNote: 'Rock-Medley (u.a. Santana, Status Quo): Vollständige Rundel-Besetzung mit Direktion, Flöten, Oboe, Klarinetten 1-3, Saxophonen, Trompeten 1-3, Flügelhörnern 1-2, Tenorhörnern 1-2, Bariton, Hörnern 1-4, Posaunen 1-3, Tuba, Drums.',
      naturallyMissingInstruments: [],
    ),
    'the greatest showman': const EditionInfo(
      title: 'The Greatest Showman',
      publisher: 'Hal Leonard',
      arranger: 'Paul Murtha',
      series: 'Young Concert Band',
      instrumentationNote: 'Enthält "This Is Me", "The Greatest Show", "A Million Dreams". Flöte, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompete 1-2, Horn in F, Posaune 1-2, Bariton, Tuba, Schlagzeug. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 3'],
    ),
    'the lion king': const EditionInfo(
      title: 'The Lion King',
      publisher: 'Hal Leonard',
      arranger: 'John Higgins',
      series: 'Concert Band',
      instrumentationNote: 'Elton John Filmmusik Medley: Flöte, Oboe, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Tuba, Percussion. Kein deutsches Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'the rose': const EditionInfo(
      title: 'The Rose',
      publisher: 'De Haske / Hal Leonard',
      arranger: 'Ron Sebregts',
      series: 'De Haske Pop Series',
      instrumentationNote: 'Bette Midler Ballade: Flöten, Oboe, Fagott, Klarinetten 1-3, Altsax 1-2, Tenorsax, Barisax, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton 1-2, Tuba, Drums. Kein Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
    'under pressure': const EditionInfo(
      title: 'Under Pressure',
      publisher: 'Hal Leonard',
      arranger: 'Rick Stitzel',
      series: 'Discovery Plus Band',
      instrumentationNote: 'Queen & David Bowie: Flöte, Klarinetten 1-2, Altsax 1-2, Tenorsax, Trompeten 1-2, F-Horn, Posaune, Bariton, Tuba, Drums. Kein Flügelhorn, kein Horn 2 im Original.',
      naturallyMissingInstruments: ['Flügelhorn', 'Waldhorn 2', 'Waldhorn 3', 'Waldhorn 4', 'Trompete 3', 'Posaune 2', 'Posaune 3'],
    ),
    'voyage, voyage': const EditionInfo(
      title: 'Voyage, Voyage',
      publisher: 'Bernaerts Music',
      arranger: 'Frank Bernaerts',
      series: 'Bernaerts Pop Series',
      instrumentationNote: 'Desireless 80er Hit: Vollständiges Concert Band Arrangement mit Zusatzstimmen für Harmonie und Fanfare.',
      naturallyMissingInstruments: [],
    ),
    'yakolo': const EditionInfo(
      title: 'Yakolo',
      publisher: 'De Haske / Tierolff',
      arranger: 'Kees Vlak / Jan Bosveld',
      series: 'Original Band Music',
      instrumentationNote: 'Originalwerk für Blasorchester: Partitur, Flöten, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Tuba, Percussion.',
      naturallyMissingInstruments: [],
    ),
    'you\'ll never walk alone': const EditionInfo(
      title: 'You\'ll Never Walk Alone',
      publisher: 'Bernaerts Music',
      arranger: 'Frank Bernaerts',
      series: 'Bernaerts Pop Series',
      instrumentationNote: 'Musical-Hymne: Flöten, Klarinetten 1-3, Saxophone, Trompeten 1-3, Hörner 1-4, Posaunen 1-3, Bariton, Tuba, Percussion. Kein deutsches Flügelhorn.',
      naturallyMissingInstruments: ['Flügelhorn'],
    ),
  };

  /// Returns known edition info for a song title or null if not specifically cataloged
  static EditionInfo? getEdition(String songTitle) {
    final clean = songTitle.toLowerCase().trim();
    if (_catalog.containsKey(clean)) {
      return _catalog[clean];
    }

    // Try partial match
    for (final entry in _catalog.entries) {
      if (clean.contains(entry.key) || entry.key.contains(clean)) {
        return entry.value;
      }
    }
    return null;
  }

  /// Builds a direct search URL on Alle-Noten.de (Germany's premier sheet music distributor)
  static String getAlleNotenSearchUrl(String title) {
    final query = '$title Blasorchester'.trim();
    return 'https://www.alle-noten.de/?cl=search&searchparam=${Uri.encodeComponent(query)}';
  }

  /// Builds a Google Search URL specifically tuned to finding the publisher instrumentation
  static String getGoogleBesetzungUrl(String title) {
    final query = '$title Blasorchester Noten Besetzung'.trim();
    return 'https://www.google.com/search?q=${Uri.encodeComponent(query)}';
  }

  /// Builds a search URL for Rundel Music Publisher (leading German Blasorchester publisher)
  static String getRundelSearchUrl(String title) {
    return 'https://www.rundel.de/de/search/?q=${Uri.encodeComponent(title)}';
  }

  /// Builds a search URL for Hal Leonard Europe
  static String getHalLeonardSearchUrl(String title) {
    return 'https://www.halleonard.com/search/search.action?keywords=${Uri.encodeComponent(title)}&subsiteid=1';
  }
}

import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/voice_matcher.dart';

class VoiceSelectorSheet extends StatelessWidget {
  final Song song;
  final PartFile currentPart;
  final MusicianProfile profile;
  final Function(PartFile) onSelectPart;

  const VoiceSelectorSheet({
    super.key,
    required this.song,
    required this.currentPart,
    required this.profile,
    required this.onSelectPart,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Stimmen-Auswahl (${song.parts.length} Stimmen vorhanden)',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.grey,
                          ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: song.parts.length,
              itemBuilder: (context, index) {
                final part = song.parts[index];
                final isCurrent = part.id == currentPart.id;
                final match = VoiceMatcher.scorePart(part, profile);

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isCurrent
                        ? Theme.of(context).primaryColor
                        : match.score >= 80
                            ? Colors.green.shade100
                            : Colors.grey.shade200,
                    foregroundColor: isCurrent
                        ? Colors.white
                        : match.score >= 80
                            ? Colors.green.shade800
                            : Colors.black87,
                    child: Icon(
                      part.fileName.toLowerCase().contains('partitur')
                          ? Icons.menu_book
                          : Icons.music_note,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    part.fileName,
                    style: TextStyle(
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    match.reason,
                    style: TextStyle(
                      color: match.score >= 80 ? Colors.green.shade700 : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  trailing: match.score >= 80
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            border: Border.all(color: Colors.green.shade300),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'Deine Stimme',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  onTap: () {
                    onSelectPart(part);
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

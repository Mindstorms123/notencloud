import 'package:flutter/material.dart';
import '../../models/musician_profile.dart';
import '../../models/song.dart';
import '../../services/voice_matcher.dart';
import '../theme/app_theme.dart';

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
    final hasExactMatch = song.parts.any((p) {
      final m = VoiceMatcher.scorePart(p, profile);
      return m.score >= 80;
    });

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.darkTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        song.isDocumentOrList
                            ? 'Dokument / Liste (${song.parts.length} Dateien)'
                            : 'Stimmenauswahl (${song.parts.length} Stimmen vorhanden)',
                        style: const TextStyle(fontSize: 13, color: AppTheme.darkTextSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppTheme.darkTextMuted),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // Explanatory banner if no exact match exists (not shown for general documents/lists)
          if (!hasExactMatch && !song.isDocumentOrList)
            Container(
              margin: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.35)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: AppTheme.amber, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Für dieses Stück ist keine ${profile.voiceNumber}. ${profile.instrument}-Stimme vorhanden. Als Ausweichstimme ist "${currentPart.fileName}" ausgewählt.',
                      style: const TextStyle(
                        color: AppTheme.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 24, color: AppTheme.darkBorder),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: song.parts.length,
              itemBuilder: (context, index) {
                final part = song.parts[index];
                final isCurrent = part.id == currentPart.id;
                final match = VoiceMatcher.scorePart(part, profile);
                final isExact = match.score >= 80;
                final isFallback = isCurrent && !isExact;

                return ListTile(
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isCurrent
                          ? (isExact
                              ? AppTheme.emerald.withValues(alpha: 0.2)
                              : AppTheme.amber.withValues(alpha: 0.2))
                          : AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(10),
                      border: isCurrent
                          ? Border.all(
                              color: isExact ? AppTheme.emerald : AppTheme.amber, width: 1.5)
                          : Border.all(color: AppTheme.darkBorder),
                    ),
                    child: Center(
                      child: Icon(
                        isCurrent ? Icons.check_circle_rounded : Icons.music_note_rounded,
                        color: isCurrent
                            ? (isExact ? AppTheme.emerald : AppTheme.amber)
                            : AppTheme.darkTextMuted,
                        size: 20,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: Text(
                          part.fileName,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                            color: isCurrent ? AppTheme.darkTextPrimary : AppTheme.darkTextSecondary,
                          ),
                        ),
                      ),
                      if (part.detectedInstrument == 'Percussion') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryLight.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppTheme.primaryLight.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            VoiceMatcher.detectPercussionSubInstrument(part.fileName),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primaryLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  subtitle: Text(
                    match.reason,
                    style: TextStyle(
                      color: isExact
                          ? AppTheme.emerald
                          : (isFallback ? AppTheme.amber : AppTheme.darkTextMuted),
                      fontSize: 12,
                    ),
                  ),
                  trailing: isExact
                      ? Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.emerald.withValues(alpha: 0.15),
                            border: Border.all(color: AppTheme.emerald.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Deine Stimme',
                            style: TextStyle(
                              color: AppTheme.emerald,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : (isFallback
                          ? Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.amber.withValues(alpha: 0.15),
                                border: Border.all(color: AppTheme.amber.withValues(alpha: 0.4)),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Ausweichstimme',
                                style: TextStyle(
                                  color: AppTheme.amber,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            )
                          : null),
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

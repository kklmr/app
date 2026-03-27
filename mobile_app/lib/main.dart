import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  runApp(const SonicWaveApp());
}

class Track {
  final int id;
  final String title;
  final String artist;
  final String minioKey;
  final String coverUrl;

  Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.minioKey,
    required this.coverUrl,
  });

  factory Track.fromJson(Map<String, dynamic> json) {
    return Track(
      id: json['id'],
      title: json['title'],
      artist: json['artist'] ?? "Unknown Artist",
      minioKey: json['minio_key'],
      coverUrl: json['cover_url'] ?? "",
    );
  }
}

class SonicWaveApp extends StatelessWidget {
  const SonicWaveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'SonicWave',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0F),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF6B4A),
          secondary: Color(0xFFFF8C6E),
          surface: Color(0xFF1A1A1F),
          background: Color(0xFF0D0D0F),
        ),
        useMaterial3: true,
        fontFamily: 'SF Pro Text',
      ),
      home: const MobileFrame(child: MusicPlayerScreen()),
    );
  }
}

class MobileFrame extends StatelessWidget {
  final Widget child;
  const MobileFrame({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0D0F),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 500),
          child: child,
        ),
      ),
    );
  }
}

class MusicPlayerScreen extends StatefulWidget {
  const MusicPlayerScreen({super.key});

  @override
  State<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends State<MusicPlayerScreen>
    with TickerProviderStateMixin {
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<Track> _tracks = [];
  List<Track> _filteredTracks = [];
  Track? _currentTrack;
  bool _isLoading = true;
  int _selectedNavIndex = 0;

  final String baseUrl = "http://172.24.12.22:30964";

  @override
  void initState() {
    super.initState();
    _fetchTracks();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _fetchTracks() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/tracks'));
      if (response.statusCode == 200) {
        List jsonResponse = json.decode(response.body);
        setState(() {
          _tracks = jsonResponse.map((data) => Track.fromJson(data)).toList();
          _filteredTracks = _tracks;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching tracks: $e");
    }
  }

  void _filterTracks(String query) {
    setState(() {
      _filteredTracks = _tracks
          .where((t) =>
              t.title.toLowerCase().contains(query.toLowerCase()) ||
              t.artist.toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  Future<void> _playTrack(Track track) async {
    if (_currentTrack?.id == track.id) {
      await _audioPlayer.seek(Duration.zero);
      await _audioPlayer.play();
      return;
    }

    setState(() => _currentTrack = track);

    try {
      await _audioPlayer.stop();
      final streamUrl = "$baseUrl/stream?key=${track.minioKey}";
      await _audioPlayer.setUrl(streamUrl);
      await _audioPlayer.play();
    } catch (e) {
      debugPrint("Error streaming: $e");
    }
  }

  void _openFullPlayer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FullPlayerPage(
        track: _currentTrack!,
        player: _audioPlayer,
        baseUrl: baseUrl,
      ),
    );
  }

  void _showUploadSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          color: Color(0xFF1A1A1F),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 20,
          ),
          child: UploadTrackForm(baseUrl: baseUrl),
        ),
      ),
    ).then((_) {
      _fetchTracks();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0D0D0F), Color(0xFF121216)],
              ),
            ),
          ),
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              _isLoading
                  ? const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFFFF6B4A),
                          strokeWidth: 3,
                        ),
                      ),
                    )
                  : SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) =>
                              _buildTrackCard(_filteredTracks[index]),
                          childCount: _filteredTracks.length,
                        ),
                      ),
                    ),
            ],
          ),
          if (_currentTrack != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: 70,
              child: _buildMiniPlayer(),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 90,
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          "SonicWave",
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: 1,
          ),
        ),
        centerTitle: false,
        titlePadding: const EdgeInsets.only(left: 16, bottom: 12),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Color(0xFFFF6B4A)),
          onPressed: _showUploadSheet,
        ),
        const SizedBox(width: 8),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1F),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              onChanged: _filterTracks,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Поиск...",
                hintStyle:
                    TextStyle(color: Colors.white.withValues(alpha: 0.4)),
                prefixIcon: const Icon(Icons.search,
                    color: Color(0xFFFF6B4A), size: 20),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrackCard(Track track) {
    bool isPlaying = _currentTrack?.id == track.id;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _playTrack(track),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isPlaying
                  ? const Color(0xFFFF6B4A).withValues(alpha: 0.1)
                  : const Color(0xFF1A1A1F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isPlaying ? const Color(0xFFFF6B4A) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _CORSImage(url: track.coverUrl, size: 48),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        style: TextStyle(
                          color: isPlaying
                              ? const Color(0xFFFF6B4A)
                              : Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  isPlaying ? Icons.equalizer : Icons.play_arrow,
                  color: isPlaying
                      ? const Color(0xFFFF6B4A)
                      : Colors.white.withValues(alpha: 0.54),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMiniPlayer() {
    return GestureDetector(
      onTap: _openFullPlayer,
      child: Container(
        height: 70,
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1F),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _CORSImage(url: _currentTrack!.coverUrl, size: 45),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentTrack!.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _currentTrack!.artist,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: _audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    icon: Icon(playing ? Icons.pause : Icons.play_arrow,
                        size: 28),
                    color: const Color(0xFFFF6B4A),
                    onPressed: playing ? _audioPlayer.pause : _audioPlayer.play,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0F),
        border: Border(
          top: BorderSide(
              color: Colors.white.withValues(alpha: 0.05), width: 0.5),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildNavItem(Icons.home_outlined, Icons.home, "Главная", 0),
              _buildNavItem(Icons.explore_outlined, Icons.explore, "Обзор", 1),
              _buildNavItem(Icons.library_music_outlined, Icons.library_music,
                  "Медиатека", 2),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
      IconData outlinedIcon, IconData filledIcon, String label, int index) {
    final isSelected = _selectedNavIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNavIndex = index;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSelected ? filledIcon : outlinedIcon,
            color: isSelected
                ? const Color(0xFFFF6B4A)
                : Colors.white.withValues(alpha: 0.54),
            size: 24,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFFFF6B4A)
                  : Colors.white.withValues(alpha: 0.54),
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class FullPlayerPage extends StatefulWidget {
  final Track track;
  final AudioPlayer player;
  final String baseUrl;

  const FullPlayerPage({
    super.key,
    required this.track,
    required this.player,
    required this.baseUrl,
  });

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0D0D0F), Color(0xFF1A1A1F)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Spacer(flex: 1),
              Hero(
                tag: 'cover-${widget.track.id}',
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF6B4A).withValues(alpha: 0.3),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _CORSImage(url: widget.track.coverUrl, size: 280),
                  ),
                ),
              ),
              const Spacer(flex: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    Text(
                      widget.track.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.track.artist,
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              _buildProgressBar(),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.skip_previous, size: 32),
                    color: Colors.white70,
                    onPressed: () => widget.player.seek(Duration.zero),
                  ),
                  const SizedBox(width: 40),
                  StreamBuilder<PlayerState>(
                    stream: widget.player.playerStateStream,
                    builder: (context, snapshot) {
                      final playing = snapshot.data?.playing ?? false;
                      return Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF6B4A), Color(0xFFFF8C6E)],
                          ),
                        ),
                        child: IconButton(
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            size: 40,
                            color: Colors.white,
                          ),
                          onPressed: playing
                              ? widget.player.pause
                              : widget.player.play,
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 40),
                  IconButton(
                    icon: const Icon(Icons.skip_next, size: 32),
                    color: Colors.white70,
                    onPressed: () => widget.player
                        .seek(widget.player.duration ?? Duration.zero),
                  ),
                ],
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return StreamBuilder<Duration>(
      stream: widget.player.positionStream,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = widget.player.duration ?? Duration.zero;
        return Column(
          children: [
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: const Color(0xFFFF6B4A),
                inactiveTrackColor: Colors.white.withValues(alpha: 0.24),
                thumbColor: const Color(0xFFFF6B4A),
                overlayColor: const Color(0xFFFF6B4A).withValues(alpha: 0.2),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: position.inMilliseconds
                    .toDouble()
                    .clamp(0, duration.inMilliseconds.toDouble()),
                max: duration.inMilliseconds.toDouble(),
                onChanged: (v) =>
                    widget.player.seek(Duration(milliseconds: v.toInt())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white60)),
                  Text(_formatDuration(duration),
                      style:
                          const TextStyle(fontSize: 12, color: Colors.white60)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    String minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    String seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$minutes:$seconds";
  }
}

class _CORSImage extends StatelessWidget {
  final String url;
  final double size;
  final double radius;

  const _CORSImage({required this.url, required this.size, this.radius = 10});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) return _placeholder();

    return FutureBuilder<Uint8List>(
      future: http.get(Uri.parse(url)).then((res) => res.bodyBytes),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.hasData) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: Image.memory(
              snapshot.data!,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          );
        }
        return _placeholder();
      },
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: const Icon(Icons.music_note, color: Colors.white38),
    );
  }
}

class UploadTrackForm extends StatefulWidget {
  final String baseUrl;
  const UploadTrackForm({super.key, required this.baseUrl});

  @override
  State<UploadTrackForm> createState() => _UploadTrackFormState();
}

class _UploadTrackFormState extends State<UploadTrackForm> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _artistController = TextEditingController();

  PlatformFile? _audioFile;
  PlatformFile? _coverFile;
  bool _isUploading = false;

  Future<void> _pickAudio() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      withData: true,
    );
    if (result != null) setState(() => _audioFile = result.files.first);
  }

  Future<void> _pickCover() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null) setState(() => _coverFile = result.files.first);
  }

  Future<void> _uploadTrack() async {
    if (_titleController.text.isEmpty ||
        _artistController.text.isEmpty ||
        _audioFile == null ||
        _coverFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Заполните все поля и выберите файлы!"),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFFF6B4A),
      ));
      return;
    }

    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse('${widget.baseUrl}/upload-track'));

      request.fields['title'] = _titleController.text;
      request.fields['artist'] = _artistController.text;

      request.files.add(http.MultipartFile.fromBytes(
        'audio',
        _audioFile!.bytes!,
        filename: _audioFile!.name,
      ));

      request.files.add(http.MultipartFile.fromBytes(
        'cover',
        _coverFile!.bytes!,
        filename: _coverFile!.name,
      ));

      var response = await request.send();

      if (response.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Трек успешно загружен!"),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
          ));
        }
      } else {
        throw Exception("Ошибка загрузки: ${response.statusCode}");
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Ошибка: $e"),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          "Новый трек",
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFFFF6B4A),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _titleController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: "Название",
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFFF6B4A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _artistController,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: "Исполнитель",
            labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.7)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: Color(0xFFFF6B4A), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickAudio,
                icon: const Icon(Icons.audiotrack),
                label: Text(_audioFile != null ? "MP3" : "MP3"),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: const Color(0xFFFF6B4A).withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickCover,
                icon: const Icon(Icons.image),
                label: Text(_coverFile != null ? "Фото" : "Фото"),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                      color: const Color(0xFFFF6B4A).withValues(alpha: 0.5)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 30),
        _isUploading
            ? const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF6B4A),
                  strokeWidth: 3,
                ),
              )
            : ElevatedButton(
                onPressed: _uploadTrack,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B4A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "Загрузить",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
        const SizedBox(height: 20),
      ],
    );
  }
}

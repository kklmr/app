package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"

	_ "github.com/lib/pq"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// Модель трека для JSON
type Track struct {
	ID       int    `json:"id"`
	Title    string `json:"title"`
	Artist   string `json:"artist"`
	MinioKey string `json:"minio_key"`
	CoverURL string `json:"cover_url"`
}

func main() {
	// --- КОНФИГУРАЦИЯ БАЗЫ ДАННЫХ ---
	dbConnStr := "host=postgres-service port=5432 user=admin password=admin123 dbname=music_db sslmode=disable"
	db, err := sql.Open("postgres", dbConnStr)
	if err != nil {
		log.Fatalf("Ошибка подключения к БД: %v", err)
	}
	defer db.Close()

	// --- КОНФИГУРАЦИЯ MINIO ---
	minioEndpoint := os.Getenv("MINIO_ENDPOINT") // Берется из манифеста K8s
	if minioEndpoint == "" {
		minioEndpoint = "172.24.12.22:9000" // Резервный адрес
	}

	minioClient, err := minio.New(minioEndpoint, &minio.Options{
		Creds:  credentials.NewStaticV4("admin", "password123", ""),
		Secure: false,
	})
	if err != nil {
		log.Fatalf("Ошибка подключения к MinIO: %v", err)
	}

	// 1. ПОЛУЧЕНИЕ СПИСКА ТРЕКОВ
	http.HandleFunc("/tracks", func(w http.ResponseWriter, r *http.Request) {
		setupCORS(w, r)
		if r.Method == "OPTIONS" {
			return
		}

		rows, err := db.Query("SELECT id, title, artist, minio_key, cover_url FROM tracks")
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		defer rows.Close()

		var tracks []Track
		for rows.Next() {
			var t Track
			if err := rows.Scan(&t.ID, &t.Title, &t.Artist, &t.MinioKey, &t.CoverURL); err != nil {
				continue
			}
			tracks = append(tracks, t)
		}

		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(tracks)
	})

	// 2. СТРИМИНГ АУДИО (С ПОДДЕРЖКОЙ ПЕРЕМОТКИ / RANGE)
	http.HandleFunc("/stream", func(w http.ResponseWriter, r *http.Request) {
		setupCORS(w, r)
		// Важно: сообщаем браузеру, что поддерживаем частичный контент
		w.Header().Set("Accept-Ranges", "bytes")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		key := r.URL.Query().Get("key")
		if key == "" {
			http.Error(w, "Missing key", 400)
			return
		}

		// Получаем объект из MinIO
		object, err := minioClient.GetObject(context.Background(), "music", key, minio.GetObjectOptions{})
		if err != nil {
			http.Error(w, "File not found", 404)
			return
		}
		defer object.Close()

		// Получаем метаданные (размер и время изменения) для ServeContent
		stat, err := object.Stat()
		if err != nil {
			http.Error(w, "File info error", 500)
			return
		}

		// Указываем тип контента
		w.Header().Set("Content-Type", "audio/mpeg")

		// КЛЮЧЕВОЙ МОМЕНТ: ServeContent обрабатывает заголовок Range автоматически.
		// Это позволяет перематывать трек и ставить на паузу без сброса.
		http.ServeContent(w, r, stat.Key, stat.LastModified, object)
	})

	// 3. ПОЛУЧЕНИЕ ОБЛОЖЕК
	http.HandleFunc("/cover", func(w http.ResponseWriter, r *http.Request) {
		setupCORS(w, r)
		w.Header().Set("Cross-Origin-Resource-Policy", "cross-origin")

		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		key := r.URL.Query().Get("key")
		object, err := minioClient.GetObject(context.Background(), "covers", key, minio.GetObjectOptions{})
		if err != nil {
			http.Error(w, "Cover not found", 404)
			return
		}
		defer object.Close()

		w.Header().Set("Content-Type", "image/jpeg")
		io.Copy(w, object)
	})

	// 4. ЗАГРУЗКА ОБЛОЖЕК
	http.HandleFunc("/upload-cover", func(w http.ResponseWriter, r *http.Request) {
		setupCORS(w, r)
		if r.Method == "OPTIONS" {
			return
		}

		r.ParseMultipartForm(10 << 20) // max 10MB
		file, header, err := r.FormFile("image")
		if err != nil {
			http.Error(w, "Invalid file", 400)
			return
		}
		defer file.Close()

		trackID := r.FormValue("id")

		// Загрузка в MinIO
		_, err = minioClient.PutObject(context.Background(), "covers", header.Filename, file, header.Size, minio.PutObjectOptions{
			ContentType: "image/jpeg",
		})
		if err != nil {
			http.Error(w, "Upload to MinIO failed", 500)
			return
		}

		// Обновляем URL в БД (используем внешний IP Ubuntu для доступа из Flutter)
		newURL := fmt.Sprintf("http://172.24.12.22:30964/cover?key=%s", header.Filename)
		_, err = db.Exec("UPDATE tracks SET cover_url = $1 WHERE id = $2", newURL, trackID)
		if err != nil {
			http.Error(w, "DB Update failed", 500)
			return
		}

		fmt.Fprintf(w, "Success! URL: %s", newURL)
	})

	// 5. ЗАГРУЗКА НОВОГО ТРЕКА (Аудио + Обложка + Метаданные)
	http.HandleFunc("/upload-track", func(w http.ResponseWriter, r *http.Request) {
		setupCORS(w, r)

		// САМОЕ ВАЖНОЕ: Если пришел OPTIONS запрос, мы просто возвращаем 200 и выходим
		if r.Method == "OPTIONS" {
			w.WriteHeader(http.StatusOK)
			return
		}

		if r.Method != "POST" {
			http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
			return
		}

		// Лимит на 50 MB
		err := r.ParseMultipartForm(50 << 20)
		if err != nil {
			log.Println("Ошибка парсинга формы:", err)
			http.Error(w, "File too large", http.StatusBadRequest)
			return
		}

		title := r.FormValue("title")
		artist := r.FormValue("artist")

		// 1. Получаем аудиофайл
		audioFile, audioHeader, err := r.FormFile("audio")
		if err != nil {
			http.Error(w, "Audio file is required", http.StatusBadRequest)
			return
		}
		defer audioFile.Close()

		// 2. Получаем обложку
		coverFile, coverHeader, err := r.FormFile("cover")
		if err != nil {
			http.Error(w, "Cover image is required", http.StatusBadRequest)
			return
		}
		defer coverFile.Close()

		// Генерируем уникальные имена файлов, чтобы не перезаписать существующие
		timestamp := time.Now().Unix()
		audioKey := fmt.Sprintf("%d_%s", timestamp, audioHeader.Filename)
		coverKey := fmt.Sprintf("%d_%s", timestamp, coverHeader.Filename)

		// 3. Загружаем аудио в MinIO (бакет "music")
		_, err = minioClient.PutObject(context.Background(), "music", audioKey, audioFile, audioHeader.Size, minio.PutObjectOptions{
			ContentType: "audio/mpeg",
		})
		if err != nil {
			http.Error(w, "Failed to upload audio to MinIO", http.StatusInternalServerError)
			return
		}

		// 4. Загружаем обложку в MinIO (бакет "covers")
		_, err = minioClient.PutObject(context.Background(), "covers", coverKey, coverFile, coverHeader.Size, minio.PutObjectOptions{
			ContentType: "image/jpeg",
		})
		if err != nil {
			http.Error(w, "Failed to upload cover to MinIO", http.StatusInternalServerError)
			return
		}

		// 5. Сохраняем информацию в PostgreSQL
		coverURL := fmt.Sprintf("http://172.24.12.22:30964/cover?key=%s", coverKey)

		var newID int
		err = db.QueryRow(
			"INSERT INTO tracks (title, artist, minio_key, cover_url) VALUES ($1, $2, $3, $4) RETURNING id",
			title, artist, audioKey, coverURL,
		).Scan(&newID)

		if err != nil {
			http.Error(w, "Failed to save to database", http.StatusInternalServerError)
			return
		}

		// Возвращаем успешный ответ
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		fmt.Fprintf(w, `{"message": "Track uploaded successfully", "id": %d}`, newID)
	})

	fmt.Println("Backend v19 (Range Support) запущен на порту :8080...")
	log.Fatal(http.ListenAndServe(":8080", nil))
}

// Помощник для настройки CORS (учитывает Range-запросы)
// 1. Принимаем просто w (интерфейс), а не *w (указатель на интерфейс)
func setupCORS(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, GET, OPTIONS, PUT, DELETE")
	w.Header().Set("Access-Control-Allow-Headers", "*")
	w.Header().Set("Access-Control-Allow-Credentials", "true")
}

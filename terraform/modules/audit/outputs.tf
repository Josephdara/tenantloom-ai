output "folder_sink_writer" {
  value = google_logging_folder_sink.audit.writer_identity
}

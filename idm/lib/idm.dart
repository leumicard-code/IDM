mod engine;
mod scanner;

use eframe::egui;
use elegance::{
  Accent, Badge, BadgeTone, Button, ButtonSize, Card, Modal, Slider, TabBar, TextInput, Theme,
};
use engine::AudioEngine;
use rand::Rng;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

const PLAYLIST_FILE: &str = "playlist.json"; // SAVE TO PLAYLIST_FILE

#[derive(PartialEq, Clone, Copy)]
enum ActiveTab {
  Library,
  Equalizer,
}

#[derive(Serialize, Deserialize, Clone)]
struct TrackItem {
  name: String,
  path: PathBuf,
}
/////////////// ////////////
struct RustRhythmsApp {
  engine: AudioEngine,
  playlist: Vec<TrackItem>,
  current_track_idx: Option<usize>,

  // Search filter
  search_query: String,

  // Controls & State
  volume: f32,
  eq_bands: [f32; 10],
  bass_boost: f32,
  shuffle_enabled: bool,
  repeat_enabled: bool,
  tab_index: usize,

  // Progress Scrubber
  is_seeking: bool,
  seek_value: f64,
  show_about_modal: bool,
  theme_is_dark: bool,
}

impl RustRhythmsApp {
  fn new(cc: &eframe::CreationContext<'_>) -> Self {
  Theme::slate().install(&cc.egui_ctx);

  setup_custom_fonts(&cc.egui_ctx); // LOAD MY FONT CTX FONT
  let playlist = Self::load_playlist();

  let engine = AudioEngine::new().expect("Failed to initialize GStreamer DSP Engine");

  Self {
    engine,
    playlist,
    current_track_idx: None,
    search_query: String::new(),
    volume: 0.8,
    eq_bands: [4.0, 3.0, 0.0, -2.0, -1.0, 1.0, 3.0, 4.0, 4.0, 5.0],
    bass_boost: 0.0,
    shuffle_enabled: false,
    repeat_enabled: false,
    tab_index: 0,
    is_seeking: false,
    seek_value: 0.0,
    show_about_modal: false,
    theme_is_dark: true,
  }
}

fn save_playlist(&self) {
  if let Ok(json) = serde_json::to_string_pretty(&self.playlist) {
    let _ = fs::write(PLAYLIST_FILE, json);
  }
}

// פונקציה לטעינת הפלייליסט מ-JSON
fn load_playlist() -> Vec<TrackItem> {
  if let Ok(data) = fs::read_to_string(PLAYLIST_FILE) {
    serde_json::from_str(&data).unwrap_or_default()
  } else {
    Vec::new()
  }
}

fn play_index(&mut self, idx: usize) {
  if idx < self.playlist.len() {
    self.current_track_idx = Some(idx);
    let path_str = self.playlist[idx].path.to_string_lossy().to_string();
    self.engine.load_file(&path_str);
  }
}

fn next_track(&mut self) {
  if self.playlist.is_empty() {
    return;
  }

  let next_idx = if self.shuffle_enabled {
    let mut rng = rand::thread_rng();
    let mut next = rng.gen_range(0..self.playlist.len());

    // הלוגיקה החדשה: מונע מהרנדום לבחור את אותו השיר שוב אם יש עוד שירים!
    if self.playlist.len() > 1 && Some(next) == self.current_track_idx {
      next = (next + 1) % self.playlist.len();
    }
    next
  } else if let Some(curr) = self.current_track_idx {
    (curr + 1) % self.playlist.len()
  } else {
    0
  };

  self.play_index(next_idx);
}

fn prev_track(&mut self) {
  if let Some(curr) = self.current_track_idx.filter(|&c| c > 0) {
    self.play_index(curr - 1);
  }
}

fn apply_preset(&mut self, preset: [f32; 10]) {
  self.eq_bands = preset;
  self.sync_equalizer();
}

fn sync_equalizer(&self) {
  for (i, &gain) in self.eq_bands.iter().enumerate() {
    let extra_bass = if i < 2 { self.bass_boost * 6.0 } else { 0.0 };
    self.engine.set_eq_band(i, (gain + extra_bass) as f64);
  }
}
}

impl eframe::App for RustRhythmsApp {
  fn ui(&mut self, ui: &mut egui::Ui, _frame: &mut eframe::Frame) {

    if self.theme_is_dark {
      // 1. אומרים למערכת לעבור למצב לילה מובנה
      ui.ctx().set_theme(egui::Theme::Dark);
      // 2. מלבישים את הסטייל היוקרתי של Slate מעל מצב הלילה
      Theme::slate().install(ui.ctx());
    } else {
      // 1. הפקודה החדשה: מאפסים את הסטייל *של מצב היום* לברירת המחדל
      ui.ctx().set_style_of(egui::Theme::Light, egui::Style::default());
      // 2. מעבירים את כל המערכת למצב יום נקי
      ui.ctx().set_theme(egui::Theme::Light);
    }

    if self.engine.is_playing() {
      ui.ctx().request_repaint_after(Duration::from_millis(250));

      if let (Some(pos), Some(dur)) = (self.engine.get_position(), self.engine.get_duration())
      {
        if dur > 0 && pos >= dur.saturating_sub(1) {
          match (self.repeat_enabled, self.current_track_idx) {
            (true, Some(curr)) => self.play_index(curr),
            _ => self.next_track(),
          }
        }
      }
    }

    // =========================================================
    // KEYBOARD SHORTCUTS (קיצורי מקשים)
    // =========================================================
    // מוודאים שהמשתמש לא מקליד כרגע בתוך תיבת חיפוש (התיקון כאן!)
    if !ui.ctx().egui_wants_keyboard_input() {
      ui.input(|i| {
        // מקש רווח: עצירה / ניגון
        if i.key_pressed(egui::Key::Space) {
          if self.engine.is_playing() {
            self.engine.pause();
          } else if self.current_track_idx.is_some() {
            self.engine.play();
          } else if !self.playlist.is_empty() {
            self.play_index(0);
          }
        }

        // חץ ימינה: שיר הבא
        if i.key_pressed(egui::Key::ArrowRight) {
          self.next_track();
        }

        // חץ שמאלה: שיר קודם
        if i.key_pressed(egui::Key::ArrowLeft) {
          self.prev_track();
        }

        // S: הדלקה/כיבוי של Shuffle (אקראי)
        if i.key_pressed(egui::Key::S) {
          self.shuffle_enabled = !self.shuffle_enabled;
        }

        // R: הדלקה/כיבוי של Repeat (לולאה)
        if i.key_pressed(egui::Key::R) {
          self.repeat_enabled = !self.repeat_enabled;
        }
      });
    }

    // =========================================================
    // TOP PANEL: Header, Tabs, Scan Button, Track Info
    // =========================================================
    egui::Panel::top("top_panel").show(ui, |ui| {
      ui.add_space(4.0);
      ui.horizontal(|ui| {
        if ui
          .add(
            Button::new("📂 Scan Folder")
            .accent(Accent::Blue)
            .size(ButtonSize::Small),
          )
          .clicked()
          {
            if let Some(folder) = rfd::FileDialog::new().pick_folder() {
              let files = scanner::find_audio_files(&folder);
              self.playlist = files
              .into_iter()
              .map(|p| {
                let name = p
                .file_name()
                .unwrap_or_default()
                .to_string_lossy()
                .to_string();
                TrackItem { name, path: p }
              })
              .collect();
              self.save_playlist();
            }
          }

          ui.separator();

          if ui
            .add(Button::new("ℹ About").size(ButtonSize::Small).outline())
            .clicked()
            {
              self.show_about_modal = true;
            }

            ui.separator();
          let theme_label = if self.theme_is_dark {
            "☀ Light"
          } else {
            "🌙 Dark"
          };
          if ui
            .add(Button::new(theme_label).size(ButtonSize::Small).outline())
            .clicked()
            {
              self.theme_is_dark = !self.theme_is_dark;
            }

            ui.separator();

          // Elegance TabBar
          ui.add(TabBar::new(
            &mut self.tab_index,
            ["📚 Library", "🎛 Equalizer"],
          ));

          ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
            if let Some(idx) = self.current_track_idx {
              if let Some(track) = self.playlist.get(idx) {
                // 1. תגית דינאמית
                if self.engine.is_playing() {
                  ui.add(Badge::new("PLAYING", BadgeTone::Ok));
                } else {
                  ui.add(Badge::new("PAUSED", BadgeTone::Warning));
                }

                // 2. שם השיר (הסמל מתווסף אוטומטית)
                ui.label(
                  egui::RichText::new(format!("🎵 {}", track.name))
                  .color(egui::Color32::from_rgb(125, 211, 252))
                  .strong(),
                );
              }

            } else {
              ui.add(Badge::new("STOPPED", BadgeTone::Neutral));
            }
          });
      });
      ui.add_space(4.0);
    });

    // =========================================================
    // BOTTOM PANEL: Controls, Scrubber, Volume (Elegance Card)
    // =========================================================
    egui::Panel::bottom("controls_panel").show(ui, |ui| {
      ui.add_space(4.0);
      Card::new().show(ui, |ui| {
        // 1. Scrubber & Time
        let pos = self.engine.get_position().unwrap_or(0) as f64;
        let dur = self.engine.get_duration().unwrap_or(0) as f64;

        ui.horizontal(|ui| {
          let current_time = if self.is_seeking {
            self.seek_value
          } else {
            pos
          };
          let pos_str = format!(
            "{}:{:02}",
            (current_time as u64) / 60,
            (current_time as u64) % 60
          );
          let dur_str = format!("{}:{:02}", (dur as u64) / 60, (dur as u64) % 60);

          ui.label(egui::RichText::new(pos_str).monospace().weak());

          let mut seek_pos = if self.is_seeking {
            self.seek_value
          } else {
            pos
          };
          let slider = ui.add(
            egui::Slider::new(&mut seek_pos, 0.0..=(dur.max(1.0))).show_value(false),
          );

          if slider.drag_started() {
            self.is_seeking = true;
          }
          if self.is_seeking {
            self.seek_value = seek_pos;
          }
          if slider.drag_stopped() {
            self.engine.seek_position(self.seek_value);
            self.is_seeking = false;
          }

          ui.label(egui::RichText::new(dur_str).monospace().weak());
        });

        ui.add_space(4.0);

        // 2. Playback Action Buttons
        ui.horizontal(|ui| {
          let mut shuf_btn = Button::new("🔀").size(ButtonSize::Small);
          if self.shuffle_enabled {
            shuf_btn = shuf_btn.accent(Accent::Blue); // דלוק: כפתור מלא וכחול
          } else {
            shuf_btn = shuf_btn.accent(Accent::Amber).outline(); // כבוי: רק מסגרת כתומה
          }
          if ui.add(shuf_btn).clicked() {
            self.shuffle_enabled = !self.shuffle_enabled;
          }

          // 2. כפתור Repeat משודרג
          let mut rep_btn = Button::new("🔁").size(ButtonSize::Small);
          if self.repeat_enabled {
            rep_btn = rep_btn.accent(Accent::Blue); // דלוק: כפתור מלא וכחול
          } else {
            rep_btn = rep_btn.accent(Accent::Amber).outline(); // כבוי: רק מסגרת כתומה
          }
          if ui.add(rep_btn).clicked() {
            self.repeat_enabled = !self.repeat_enabled;
          }

          ui.separator();

          if ui
            .add(Button::new("⏮").size(ButtonSize::Small).outline())
            .clicked()
            {
              self.prev_track();
            }

            let is_playing = self.engine.is_playing();
          let play_text = if is_playing { "⏸ Pause" } else { "▶ Play" };
          let play_accent = if is_playing {
            Accent::Amber
          } else {
            Accent::Green
          };

          if ui
            .add(
              Button::new(play_text)
              .accent(play_accent)
              .size(ButtonSize::Medium),
            )
            .clicked()
            {
              if is_playing {
                self.engine.pause();
              } else if self.current_track_idx.is_some() {
                self.engine.play();
              } else if !self.playlist.is_empty() {
                self.play_index(0);
              }
            }

            if ui
              .add(Button::new("⏹ Stop").size(ButtonSize::Small).outline())
              .clicked()
              {
                self.engine.stop();
              }

              if ui
                .add(Button::new("⏭").size(ButtonSize::Small).outline())
                .clicked()
                {
                  self.next_track();
                }

                // Volume Slider
                ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                  let vol_slider = ui
                  .add(egui::Slider::new(&mut self.volume, 0.0..=1.0).show_value(false));
                  if vol_slider.changed() {
                    self.engine.set_volume(self.volume as f64);
                  }
                  ui.label("🔊");
                });
        });
      });
      ui.add_space(4.0);
    });

    // =========================================================
    // CENTRAL PANEL: Tab Content (Library / Equalizer)
    // =========================================================
    if self.tab_index == 0 {
      // LIBRARY TAB
      Card::new().heading("📋 Music Library").show(ui, |ui| {
        ui.horizontal(|ui| {
          ui.add(
            TextInput::new(&mut self.search_query)
            .hint("Search tracks by name...")
            .label("🔍"),
          );
          if !self.playlist.is_empty() {
            ui.add(Badge::new(
              format!("{} tracks", self.playlist.len()),
                BadgeTone::Info,
            ));
          }
        });

        ui.separator();

        if self.playlist.is_empty() {
          ui.vertical_centered(|ui| {
            ui.add_space(40.0);
            ui.label(
              egui::RichText::new(
                "No files loaded. Click 'Scan Folder' above to get started.",
              )
              .weak(),
            );
          });
        } else {
          let mut track_to_play = None;
          let filter = self.search_query.to_lowercase();

          egui::ScrollArea::vertical().show(ui, |ui| {
            for (idx, track) in self.playlist.iter().enumerate() {
              if !filter.is_empty() && !track.name.to_lowercase().contains(&filter) {
                continue;
              }

              let is_selected = self.current_track_idx == Some(idx);
              ui.horizontal(|ui| {
                let icon = if is_selected && self.engine.is_playing() {
                  "🔊"
                } else {
                  "🎵"
                };
                let label_text =
                format!("{}  {:02}. {}", icon, idx + 1, track.name);

                let resp = ui.selectable_label(
                  is_selected,
                  egui::RichText::new(label_text).strong(),
                );

                if resp.double_clicked() || resp.clicked() {
                  track_to_play = Some(idx);
                }
              });
            }
          });

          if let Some(idx) = track_to_play {
            self.play_index(idx);
          }
        }
      });
    } else {
      // EQUALIZER TAB
      Card::new()
      .heading("🎛 10-Band Equalizer & DSP")
      .show(ui, |ui| {
        ui.horizontal(|ui| {
          ui.label("Presets:");
          if ui
            .add(Button::new("Flat").size(ButtonSize::Small).outline())
            .clicked()
            {
              self.apply_preset([0.0; 10]);
            }
            if ui
              .add(
                Button::new("Bass Boost")
                .size(ButtonSize::Small)
                .accent(Accent::Amber),
              )
              .clicked()
              {
                self.apply_preset([6.0, 5.0, 4.0, 2.0, 0.0, 0.0, 1.0, 2.0, 3.0, 3.0]);
              }
              if ui
                .add(
                  Button::new("Electronic")
                  .size(ButtonSize::Small)
                  .accent(Accent::Blue),
                )
                .clicked()
                {
                  self.apply_preset([4.0, 3.0, 0.0, -2.0, -1.0, 1.0, 3.0, 4.0, 4.0, 5.0]);
                }
                if ui
                  .add(
                    Button::new("Vocal Clear")
                    .size(ButtonSize::Small)
                    .accent(Accent::Purple),
                  )
                  .clicked()
                  {
                    self.apply_preset([-2.0, -1.0, 0.0, 2.0, 4.0, 4.0, 3.0, 2.0, 1.0, 0.0]);
                  }
        });

        ui.add_space(10.0);

        ui.add(
          Slider::new(&mut self.bass_boost, 0.0..=1.0)
          .label("🔥 Bass Boost Extra")
          .accent(Accent::Amber),
        );
        self.sync_equalizer();

        ui.add_space(15.0);

        let freqs = [
          "32", "64", "125", "250", "500", "1K", "2K", "4K", "8K", "16K",
        ];
        ui.allocate_ui(egui::vec2(ui.available_width(), 160.0), |ui| {
          ui.columns(10, |columns| {
            for (i, freq_label) in freqs.iter().enumerate() {
              columns[i].vertical_centered(|ui| {
                ui.label(
                  egui::RichText::new(format!("{:+0.0}dB", self.eq_bands[i]))
                  .weak()
                  .size(11.0),
                );

                ui.add_space(4.0);

                let slider = ui.add(
                  egui::Slider::new(&mut self.eq_bands[i], -12.0..=12.0)
                  .vertical()
                  .show_value(false),
                );
                if slider.changed() {
                  self.sync_equalizer();
                }

                ui.add_space(4.0);
                ui.label(egui::RichText::new(*freq_label).strong().size(12.0));
              });
            }
          });
        });
      });

      ui.add_space(8.0);

      // =========================================================
      // התיקון לחלל השחור: כרטיס "מנגן כעת" ענק ומרשים
      // =========================================================
      Card::new().show(ui, |ui| {
        // מותח את הכרטיס על כל השטח שנשאר במסך
        ui.set_min_height(ui.available_height());

        ui.vertical_centered(|ui| {
          // מוסיף רווח מלמעלה כדי לדחוף את הטקסט בדיוק לאמצע הכרטיס
          ui.add_space(ui.available_height() / 2.5);

          if let Some(idx) = self.current_track_idx {
            if let Some(track) = self.playlist.get(idx) {
              ui.label(egui::RichText::new("NOW PLAYING").weak().size(14.0));

              ui.add_space(8.0);
              ui.label(
                egui::RichText::new(&track.name)
                .strong()
                .size(28.0) // גופן ענק
                .color(egui::Color32::from_rgb(125, 211, 252)),
              );
            }
          } else {
            ui.label(egui::RichText::new("Silence...").weak().size(24.0));
            ui.add_space(8.0);
            ui.label(
              egui::RichText::new("Pick a track from the library")
              .weak()
              .size(14.0),
            );
          }
        });
      });

      if self.show_about_modal {
        let mut is_open = self.show_about_modal;
        let mut clicked_close = false; // 1. משתנה עזר חדש

        Modal::new("about_modal", &mut is_open)
        .heading("About Rust Rhythms")
        .show(ui.ctx(), |ui| {
          ui.label(
            egui::RichText::new("Rust Rhythms - LLVM Compiler Infrastructure")
            .strong()
            .size(18.0)
            .color(egui::Color32::from_rgb(125, 211, 252)),
          );
          ui.add_space(8.0);
          ui.label("Developed by: Shai Kadosh");
          ui.label("Version: 1.0.0 (2026 Edition)");

          ui.add_space(12.0);

          ui.label("Built with 🦀 Rust, egui, and GStreamer.");
          ui.label("Delivering Bare-Metal performance and pristine audio DSP.");

          ui.add_space(16.0);

          ui.horizontal(|ui| {
            if ui
              .add(Button::new("Awesome!").accent(Accent::Blue))
              .clicked()
              {
                clicked_close = true; // 2. מעדכנים את המשתנה החיצוני במקום את is_open
              }
          });
        });

        // 3. משנים את המצב רק אחרי שהמודאל סיים להתרנדר ושחרר את הנעילה!
        if clicked_close {
          is_open = false;
        }

        self.show_about_modal = is_open;
      }
    }
  }
}

fn main() -> eframe::Result<()> {
  gstreamer::init().expect("Failed to initialize GStreamer");

  let native_options = eframe::NativeOptions {
    viewport: egui::ViewportBuilder::default()
    .with_inner_size([740.0, 600.0])
    .with_min_inner_size([550.0, 450.0])
    .with_title("Rust Rhythms - LLVM Compiler Infrastructure"),
    ..Default::default()
  };

  eframe::run_native(
    "Rust Rhythms",
    native_options,
    Box::new(|cc| Ok(Box::new(RustRhythmsApp::new(cc)))),
  )
}

fn setup_custom_fonts(ctx: &egui::Context) {
  let mut fonts = egui::FontDefinitions::default();

  // הטמעת קובץ הגופן ישירות לתוך ה-Binary בזמן קימפול
  fonts.font_data.insert(
    "hebrew_font".to_owned(),
    Arc::new(egui::FontData::from_static(include_bytes!(
      "../assets/rb.ttf"
    ))),
  );

  // הסוד: משתמשים ב-insert(0) כדי לדחוף את הפונט שלנו למקום הראשון בעדיפות!
  fonts
  .families
  .entry(egui::FontFamily::Proportional)
  .or_default()
  .insert(0, "hebrew_font".to_owned());

  fonts
  .families
  .entry(egui::FontFamily::Monospace)
  .or_default()
  .insert(0, "hebrew_font".to_owned());

  ctx.set_fonts(fonts);
}

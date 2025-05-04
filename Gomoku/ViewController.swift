import UIKit
import AVFoundation // <-- Import AVFoundation for audio

class ViewController: UIViewController {

    // --- Outlets ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    @IBOutlet weak var resetButton: UIButton!

    // --- Game Constants ---
    let boardSize = 15
    var cellSize: CGFloat = 0
    var boardPadding: CGFloat = 10

    // --- Game State ---
    enum Player { case black, white }
    enum CellState { case empty, black, white }
    var currentPlayer: Player = .black
    var board: [[CellState]] = []
    var gameOver = false
    var pieceViews: [[UIView?]] = []

    // --- Adaptive Setup UI Properties ---
    private var setupPortraitConstraints: [NSLayoutConstraint] = []
    private var setupLandscapeConstraints: [NSLayoutConstraint] = []
    private var currentSetupConstraints: [NSLayoutConstraint] = [] // Track active set

    // --- AI Control ---
    enum AIDifficulty { case easy, medium, hard } // Keep 'hard' enum value
    let aiPlayer: Player = .white
    private var selectedDifficulty: AIDifficulty = .easy
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }

    // --- NEW: Minimax AI Constants ---
    private let MAX_DEPTH = 2 // Initial search depth (Adjust for performance/strength)
    private let WIN_SCORE = 1000000 // Score for winning state
    private let LOSE_SCORE = -1000000 // Score for losing state
    private let DRAW_SCORE = 0
    // Score values for patterns (adjust weights as needed)
    private let SCORE_OPEN_FOUR = 50000
    private let SCORE_CLOSED_FOUR = 4500
    private let SCORE_OPEN_THREE = 4000
    private let SCORE_CLOSED_THREE = 500
    private let SCORE_OPEN_TWO = 100
    private let SCORE_CLOSED_TWO = 10
    // --- End Minimax Constants ---
    
    // --- Layer References ---
    var backgroundGradientLayer: CAGradientLayer?
    var woodBackgroundLayers: [CALayer] = []
    private var lastDrawnBoardBounds: CGRect = .zero
    private var winningLineLayer: CAShapeLayer? // For win line

    // --- Game Setup State ---
    enum GameState { case setup, playing }
    enum GameMode { case humanVsHuman, humanVsAI }
    private var currentGameState: GameState = .setup
    private var currentGameMode: GameMode = .humanVsHuman

    // --- Setup UI Elements ---
    private let gameTitleLabel = UILabel()
    private let setupTitleLabel = UILabel()
    private let startEasyAIButton = UIButton(type: .system)
    private let startMediumAIButton = UIButton(type: .system)
    private let startHardAIButton = UIButton(type: .system) // ADD HARD AI BUTTON BACK
    private let startHvsHButton = UIButton(type: .system)
    private var setupUIElements: [UIView] = []
    private let moveCountLabel = UILabel() // <-- ADD
    private var moveCount = 0

    // --- Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)

    // --- Visual Polish Properties ---
    private var lastMovePosition: Position? = nil
    private var lastMoveIndicatorLayer: CALayer?
    private var shakeAnimation: CABasicAnimation? // To create shake only once
    private var turnIndicatorView: UIView?

    // --- Game Over Overlay UI Elements ---
    private let gameOverOverlayView = UIVisualEffectView()
    private let gameOverStatusLabel = UILabel()
    private let playAgainButton = UIButton(type: .system)
    private let overlayMainMenuButton = UIButton(type: .system)
    private var gameOverUIElements: [UIView] = []

    // --- Constraint Activation Flag ---
    private var constraintsActivated = false

    // --- Stored property for winning positions ---
    private var lastWinningPositions: [Position]? = nil

    // --- NEW: Audio & Haptic Properties ---
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light) // For general taps
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator() // For win/loss/error

    // --- Lifecycle Methods ---
    override func viewDidLoad() {
        super.viewDidLoad()
        print("viewDidLoad starting...")
        setupAudio() // <-- Setup audio players
        prepareHaptics() // <-- Prepare haptic engine
        createMoveCountLabel()
        setupMainBackground()
        styleStatusLabel()
        boardView.backgroundColor = .clear
        styleResetButton()
        createMainMenuButton()
        createSetupUI()
        createNewGameOverUI()
        setupTurnIndicatorView()
        setupNewGameVariablesOnly()
        showSetupUI()
        print("viewDidLoad completed.")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        if !constraintsActivated {
            print("viewWillLayoutSubviews: Setting up ALL constraints for the first time.")
            setupConstraints()
            setupSetupUIConstraints()
            setupMainMenuButtonConstraints()
            setupGameOverUIConstraints()
            setupMoveCountLabelConstraints()
            constraintsActivated = true
        }
        applyAdaptiveSetupConstraints()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.backgroundGradientLayer?.frame = self.view.bounds

        guard currentGameState == .playing else { return }

        let currentBoardBounds = boardView.bounds
        guard currentBoardBounds.width > 0, currentBoardBounds.height > 0 else {
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        let potentialCellSize = calculateCellSize()
        guard potentialCellSize > 0 else {
            if lastDrawnBoardBounds != .zero { lastDrawnBoardBounds = .zero }
            return
        }

        if currentBoardBounds != lastDrawnBoardBounds || self.cellSize == 0 {
            print("--> Board bounds changed or initial draw needed. Performing visual update.")
            self.cellSize = potentialCellSize
            boardView.layer.cornerRadius = 10
            boardView.layer.masksToBounds = false
            drawProceduralWoodBackground()
            drawBoard()
            redrawPieces()
            lastDrawnBoardBounds = currentBoardBounds
            print("viewDidLayoutSubviews: Visual update complete with cellSize: \(self.cellSize)")

            if gameOver, let lastWinPos = self.lastWinningPositions {
                drawWinningLine(positions: lastWinPos) // Redraw win line and highlights
            }
            if let lastPos = self.lastMovePosition, !gameOver {
                lastMoveIndicatorLayer?.removeFromSuperlayer()
                lastMoveIndicatorLayer = nil
                showLastMoveIndicator(at: lastPos)
            }
        }
    }
    
    // --- NEW: Audio Setup ---
    func setupAudio() {
        // Load sounds - replace filenames if yours are different!
        loadSound(filename: "./place_stone.mp3", key: "place")
        loadSound(filename: "./win_sound.mp3", key: "win")
        loadSound(filename: "./lose_sound.mp3", key: "lose")
        loadSound(filename: "./invalid_move.mp3", key: "invalid")
        
        // Configure audio session (optional but good practice)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
        }
    }

    func loadSound(filename: String, key: String) {
        guard let url = Bundle.main.url(forResource: filename, withExtension: nil) else {
            print("Error: Could not find sound file - \(filename)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay() // Preload buffer
            audioPlayers[key] = player
            print("Loaded sound: \(filename) as key: \(key)")
        } catch {
            print("Error loading sound \(filename): \(error)")
        }
    }

    func playSound(key: String) {
        guard let player = audioPlayers[key] else {
            print("Warning: Sound player for key '\(key)' not found.")
            return
        }

        // If the sound needs to interrupt itself (like rapid piece placement)
        if key == "place" && player.isPlaying {
             player.stop() // Only stop the "place" sound if it's already playing
        }
        
        // Always rewind and play
        player.currentTime = 0
        player.play()
    }


    // --- NEW: Haptic Setup ---
    func prepareHaptics() {
        impactFeedbackGenerator.prepare()
        notificationFeedbackGenerator.prepare()
        print("Haptic generators prepared.")
    }

    // --- Constraints Setup (Game elements, Setup UI, Menu, Game Over) ---
    // ... setupConstraints(), createSetupUI(), configureSetupButton(), setupSetupUIConstraints(), applyAdaptiveSetupConstraints() ... (Keep existing code, including Hard button UI/logic)
    func setupConstraints() {
        guard let statusLabel = statusLabel, let boardView = boardView, let resetButton = resetButton else { print("Error: Outlets not connected for game elements!"); return }
        guard !self.view.constraints.contains(where: { $0.firstItem === boardView || $0.secondItem === boardView }) else { return }

        print("Setting up game element constraints..."); statusLabel.translatesAutoresizingMaskIntoConstraints = false; boardView.translatesAutoresizingMaskIntoConstraints = false; resetButton.translatesAutoresizingMaskIntoConstraints = false
        let safeArea = view.safeAreaLayoutGuide
        let centerXConstraint = boardView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor); let centerYConstraint = boardView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor)
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0); aspectRatioConstraint.priority = .required; let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20); let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80)
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80); let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40); widthConstraint.priority = .defaultHigh
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160); heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([centerXConstraint, centerYConstraint, aspectRatioConstraint, leadingConstraint, trailingConstraint, topConstraint, bottomConstraint, widthConstraint, heightConstraint])
        NSLayoutConstraint.activate([statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20), statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)])
        NSLayoutConstraint.activate([resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30), resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30), resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)])
        print("Game element constraints activated.")
    }
     func createSetupUI() {
        print("Creating Setup UI")
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false; gameTitleLabel.text = "Gomoku"; gameTitleLabel.font = UIFont.systemFont(ofSize: 48, weight: .bold); gameTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); gameTitleLabel.textAlignment = .center; gameTitleLabel.layer.shadowColor = UIColor.black.cgColor; gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 2); gameTitleLabel.layer.shadowRadius = 4.0; gameTitleLabel.layer.shadowOpacity = 0.2; gameTitleLabel.layer.masksToBounds = false; view.addSubview(gameTitleLabel)
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false; setupTitleLabel.text = "Choose Game Mode"; setupTitleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold); setupTitleLabel.textColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); setupTitleLabel.textAlignment = .center; view.addSubview(setupTitleLabel)
        startEasyAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startEasyAIButton, color: UIColor(red: 0.8, green: 0.95, blue: 0.85, alpha: 1.0)); startEasyAIButton.setTitle("vs AI (Easy)", for: .normal); startEasyAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside); view.addSubview(startEasyAIButton)
        startMediumAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startMediumAIButton, color: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1.0)); startMediumAIButton.setTitle("vs AI (Medium)", for: .normal); startMediumAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside); view.addSubview(startMediumAIButton)
        startHardAIButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHardAIButton, color: UIColor(red: 0.95, green: 0.75, blue: 0.75, alpha: 1.0)); startHardAIButton.setTitle("vs AI (Hard)", for: .normal); startHardAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside); view.addSubview(startHardAIButton)
        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false; configureSetupButton(startHvsHButton, color: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1.0)); startHvsHButton.setTitle("Human vs Human", for: .normal); startHvsHButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside); view.addSubview(startHvsHButton)
        setupUIElements = [gameTitleLabel, setupTitleLabel, startEasyAIButton, startMediumAIButton, startHardAIButton, startHvsHButton]
    }
    func configureSetupButton(_ button: UIButton, color: UIColor) {
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold);
        button.backgroundColor = color; button.setTitleColor(.darkText, for: .normal); button.layer.cornerRadius = 14
        if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.baseBackgroundColor = color; config.baseForegroundColor = .darkText; config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 30, bottom: 15, trailing: 30); config.cornerStyle = .large; config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = UIFont.systemFont(ofSize: 22, weight: .bold); return outgoing }; button.configuration = config }
        else { button.contentEdgeInsets = UIEdgeInsets(top: 15, left: 30, bottom: 15, right: 30) }
        button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 3; button.layer.shadowOpacity = 0.15; button.layer.masksToBounds = false
    }
     func setupSetupUIConstraints() { /* ... no changes needed here ... */
         print("Setting up Setup UI constraints (V4 - With Hard Button)")
         setupPortraitConstraints.removeAll(); setupLandscapeConstraints.removeAll()
         guard setupUIElements.count == 6 else { print("Error: Setup UI elements count mismatch (\(setupUIElements.count)). Expected 6."); return }
         let safeArea = view.safeAreaLayoutGuide; let verticalSpacingMultiplier: CGFloat = 0.04; let buttonHeightMultiplier: CGFloat = 0.09; let buttonWidthMultiplier: CGFloat = 0.65
         setupPortraitConstraints = [ gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: view.bounds.height * 0.12), gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), gameTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), gameTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: view.bounds.height * 0.02), setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), setupTitleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), setupTitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: view.bounds.height * 0.05), startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startEasyAIButton.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: buttonWidthMultiplier), startEasyAIButton.heightAnchor.constraint(equalTo: safeArea.heightAnchor, multiplier: buttonHeightMultiplier), startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier), startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startMediumAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), startHardAIButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier), startHardAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startHardAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.bottomAnchor, constant: view.bounds.height * verticalSpacingMultiplier), startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startHvsHButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), ]
         let landscapeButtonWidthMultiplier: CGFloat = 0.35; let landscapeVerticalSpacing: CGFloat = view.bounds.height * 0.03
         setupLandscapeConstraints = [ gameTitleLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 5), gameTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), setupTitleLabel.topAnchor.constraint(equalTo: gameTitleLabel.bottomAnchor, constant: view.bounds.height * 0.02), setupTitleLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startEasyAIButton.topAnchor.constraint(equalTo: setupTitleLabel.bottomAnchor, constant: view.bounds.height * 0.05), startEasyAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startEasyAIButton.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: landscapeButtonWidthMultiplier), startEasyAIButton.heightAnchor.constraint(equalTo: safeArea.heightAnchor, multiplier: buttonHeightMultiplier * 1.2), startMediumAIButton.topAnchor.constraint(equalTo: startEasyAIButton.bottomAnchor, constant: landscapeVerticalSpacing), startMediumAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startMediumAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startMediumAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), startHardAIButton.topAnchor.constraint(equalTo: startMediumAIButton.bottomAnchor, constant: landscapeVerticalSpacing), startHardAIButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startHardAIButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startHardAIButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), startHvsHButton.topAnchor.constraint(equalTo: startHardAIButton.bottomAnchor, constant: landscapeVerticalSpacing), startHvsHButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), startHvsHButton.widthAnchor.constraint(equalTo: startEasyAIButton.widthAnchor), startHvsHButton.heightAnchor.constraint(equalTo: startEasyAIButton.heightAnchor), ]
         print("Setup UI constraint sets V4 created.")
     }
    func applyAdaptiveSetupConstraints() { /* ... no changes needed here ... */
        guard constraintsActivated else { return }
        let isLandscape = view.bounds.width > view.bounds.height; let targetConstraints = isLandscape ? setupLandscapeConstraints : setupPortraitConstraints
        if currentSetupConstraints == targetConstraints && !currentSetupConstraints.isEmpty { return }
        if !currentSetupConstraints.isEmpty { NSLayoutConstraint.deactivate(currentSetupConstraints) }
        if !targetConstraints.isEmpty { NSLayoutConstraint.activate(targetConstraints); currentSetupConstraints = targetConstraints }
        else { print("Warning: Target constraint set is empty for \(isLandscape ? "Landscape" : "Portrait")."); currentSetupConstraints = [] }
    }
    func createMainMenuButton() { /* ... no changes needed here ... */ print("Creating Main Menu Button"); mainMenuButton.translatesAutoresizingMaskIntoConstraints = false; if #available(iOS 15.0, *) { var config = UIButton.Configuration.plain(); config.title = "‹ Menu"; config.titleAlignment = .leading; config.baseForegroundColor = UIColor.systemBlue; config.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 10); mainMenuButton.configuration = config } else { mainMenuButton.setTitle("‹ Menu", for: .normal); mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .medium); mainMenuButton.setTitleColor(UIColor.systemBlue, for: .normal); mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 5, left: 0, bottom: 5, right: 10) }; mainMenuButton.backgroundColor = .clear; mainMenuButton.addTarget(self, action: #selector(didTapMenuButton), for: .touchUpInside); mainMenuButton.isHidden = true; view.addSubview(mainMenuButton) }
    func setupMainMenuButtonConstraints() { /* ... no changes needed here ... */ print("Setting up Main Menu Button constraints"); let safeArea = view.safeAreaLayoutGuide; NSLayoutConstraint.activate([ mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15), mainMenuButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20) ]) }
    func createNewGameOverUI() { /* ... no changes needed here ... */ print("Creating Game Over UI with Blur"); gameOverOverlayView.translatesAutoresizingMaskIntoConstraints = false; gameOverOverlayView.effect = UIBlurEffect(style: .systemMaterialDark); gameOverOverlayView.layer.cornerRadius = 15; gameOverOverlayView.layer.masksToBounds = true; gameOverOverlayView.isHidden = true; gameOverOverlayView.contentView.addSubview(gameOverStatusLabel); gameOverOverlayView.contentView.addSubview(playAgainButton); gameOverOverlayView.contentView.addSubview(overlayMainMenuButton); view.addSubview(gameOverOverlayView); gameOverStatusLabel.translatesAutoresizingMaskIntoConstraints = false; gameOverStatusLabel.font = UIFont.systemFont(ofSize: 32, weight: .bold); gameOverStatusLabel.textColor = .white; gameOverStatusLabel.textAlignment = .center; gameOverStatusLabel.numberOfLines = 0; playAgainButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(playAgainButton, title: "Play Again", color: UIColor.systemGreen.withAlphaComponent(0.8)); playAgainButton.addTarget(self, action: #selector(didTapGameOverButton(_:)), for: .touchUpInside); overlayMainMenuButton.translatesAutoresizingMaskIntoConstraints = false; configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: UIColor.systemBlue.withAlphaComponent(0.8)); overlayMainMenuButton.addTarget(self, action: #selector(didTapGameOverButton(_:)), for: .touchUpInside); gameOverUIElements = [gameOverOverlayView, gameOverStatusLabel, playAgainButton, overlayMainMenuButton] }
    func configureGameOverButton(_ button: UIButton, title: String, color: UIColor) { /* ... no changes needed here ... */ button.setTitle(title, for: .normal); if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.baseBackgroundColor = color; config.baseForegroundColor = .white; config.cornerStyle = .medium; config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in var outgoing = incoming; outgoing.font = UIFont.systemFont(ofSize: 18, weight: .semibold); return outgoing }; config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20); button.configuration = config } else { button.backgroundColor = color; button.setTitleColor(.white, for: .normal); button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold); button.layer.cornerRadius = 8; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20) }; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 3; button.layer.shadowOpacity = 0.3; button.layer.masksToBounds = false }
    func setupGameOverUIConstraints() { /* ... no changes needed here ... */ print("Setting up Game Over UI constraints"); let safeArea = view.safeAreaLayoutGuide; let buttonSpacing: CGFloat = 20; let overlayContentView = gameOverOverlayView.contentView; NSLayoutConstraint.activate([ gameOverOverlayView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), gameOverOverlayView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor), gameOverOverlayView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 0.7), gameOverOverlayView.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.5), gameOverStatusLabel.topAnchor.constraint(equalTo: overlayContentView.topAnchor, constant: 30), gameOverStatusLabel.leadingAnchor.constraint(equalTo: overlayContentView.leadingAnchor, constant: 20), gameOverStatusLabel.trailingAnchor.constraint(equalTo: overlayContentView.trailingAnchor, constant: -20), playAgainButton.topAnchor.constraint(equalTo: gameOverStatusLabel.bottomAnchor, constant: 30), playAgainButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.topAnchor.constraint(equalTo: playAgainButton.bottomAnchor, constant: buttonSpacing), overlayMainMenuButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor), overlayMainMenuButton.widthAnchor.constraint(equalTo: playAgainButton.widthAnchor), overlayMainMenuButton.bottomAnchor.constraint(lessThanOrEqualTo: overlayContentView.bottomAnchor, constant: -30) ]) }
    
    // --- Turn Indicator (Underline) ---
    func setupTurnIndicatorView() { /* ... no changes needed ... */ guard statusLabel != nil else { return }; let indicator = UIView(); indicator.translatesAutoresizingMaskIntoConstraints = false; indicator.backgroundColor = .clear; indicator.layer.cornerRadius = 1.5; indicator.isHidden = true; view.addSubview(indicator); self.turnIndicatorView = indicator; NSLayoutConstraint.activate([indicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4), indicator.heightAnchor.constraint(equalToConstant: 3), indicator.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor)]); print("Turn indicator view created.") }
    func updateTurnIndicatorLine() { /* ... no changes needed ... */ guard let indicator = turnIndicatorView, let label = statusLabel else { return }; let targetColor: UIColor; let targetWidth: CGFloat; if gameOver || currentGameState != .playing { targetColor = .clear; targetWidth = 0 } else { targetColor = (currentPlayer == .black) ? .black : UIColor(white: 0.9, alpha: 0.9); targetWidth = label.intrinsicContentSize.width * 0.6 }; UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: { indicator.backgroundColor = targetColor; if let widthConstraint = indicator.constraints.first(where: { $0.firstAttribute == .width }) { widthConstraint.constant = targetWidth } else { indicator.widthAnchor.constraint(equalToConstant: targetWidth).isActive = true }; indicator.superview?.layoutIfNeeded() }, completion: nil); indicator.isHidden = (gameOver || currentGameState != .playing) }

    // --- Visibility Functions ---
    func showSetupUI() {
        print("Showing Setup UI")
        // Hide game elements instantly BEFORE transition
        statusLabel.isHidden = true
        boardView.isHidden = true
        resetButton.isHidden = true
        mainMenuButton.isHidden = true
        moveCountLabel.isHidden = true // Hide move count label
        gameOverOverlayView.isHidden = true // Ensure overlay is hidden
        turnIndicatorView?.isHidden = true

        // Remove gesture recognizer
        boardView.gestureRecognizers?.forEach { boardView.removeGestureRecognizer($0) }

        let setupElementsToShow = setupUIElements + [gameTitleLabel]

        // Transition TO Setup UI
        UIView.transition(with: self.view, duration: 0.35, options: .transitionCrossDissolve, animations: {
            setupElementsToShow.forEach { $0.isHidden = false }
            self.currentGameState = .setup // Set state during animation
        }, completion: { _ in
             print("showSetupUI transition complete.")
        })
    }

    func showGameUI() {
        print("Showing Game UI")
        // Hide setup elements instantly BEFORE transition
        setupUIElements.forEach { $0.isHidden = true }
        gameTitleLabel.isHidden = true

        let gameElementsToShow = [statusLabel, boardView, resetButton, mainMenuButton, moveCountLabel] // Add move count label

        // Transition TO Game UI
        UIView.transition(with: self.view, duration: 0.35, options: .transitionCrossDissolve, animations: {
            gameElementsToShow.forEach { $0?.isHidden = false } // Use optional chaining for outlets
            self.turnIndicatorView?.isHidden = false
            self.currentGameState = .playing // Set state during animation
        }, completion: { [weak self] _ in
            guard let self = self else { return }
            print("showGameUI transition complete.")
            // Add gesture recognizer AFTER transition
            if self.boardView.gestureRecognizers?.isEmpty ?? true {
                 self.addTapGestureRecognizer()
            }
            // Update indicators AFTER transition
            DispatchQueue.main.async {
                self.updateTurnIndicatorLine()
            }
        })
    }
    func showGameOverOverlay(message: String) { /* ... no changes needed ... */
        print("Showing Game Over Overlay: \(message)")
        
        // --- ADDED: Add flair to message ---
        let displayMessage: String
        if message.contains("Wins") {
             // Using "trophy.fill" SF Symbol
             displayMessage = "🏆 " + message
        } else {
             // Draw message
             displayMessage = "🤝 " + message // Example: Handshake for draw
        }
        gameOverStatusLabel.text = displayMessage
        // --- End Flair ---

        gameOverOverlayView.isHidden = false
        gameOverOverlayView.alpha = 0
        gameOverOverlayView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1); view.bringSubviewToFront(gameOverOverlayView); resetButton.isHidden = true; mainMenuButton.isHidden = true; UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.3, options: .curveEaseOut, animations: { self.gameOverOverlayView.alpha = 1.0; self.gameOverOverlayView.transform = .identity }, completion: nil); view.isUserInteractionEnabled = true; turnIndicatorView?.isHidden = true }
    func hideGameOverOverlay() { /* ... no changes needed ... */ print("Hiding Game Over Overlay"); UIView.animate(withDuration: 0.2, animations: { self.gameOverOverlayView.alpha = 0.0; self.gameOverOverlayView.transform = CGAffineTransform(scaleX: 0.9, y: 0.9) }) { _ in self.gameOverOverlayView.isHidden = true; self.gameOverOverlayView.transform = .identity; if self.currentGameState == .playing { self.resetButton.isHidden = false; self.mainMenuButton.isHidden = false; self.turnIndicatorView?.isHidden = self.gameOver } } }

    // --- Button Actions ---
    // --- NEW: Button Animation Helpers ---
    private func animateButtonDown(_ button: UIButton) {
        // Ensure identity before starting
        button.transform = .identity
        button.alpha = 1.0

        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
            button.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
            button.alpha = 0.75 // Use alpha for consistent effect across button types
        }, completion: nil)
    }

    private func animateButtonUp(_ button: UIButton) {
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseIn], animations: {
            button.transform = .identity
            button.alpha = 1.0
        }, completion: nil)
    }
    
    // Combine setup button taps
    // --- Button Actions ---
    @objc func didTapSetupButton(_ sender: UIButton) {
        animateButtonUp(sender) // Animate up on release inside
        impactFeedbackGenerator.impactOccurred()
        // Add touch down event to trigger down animation
        sender.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        sender.addTarget(self, action: #selector(buttonTouchDragExit(_:)), for: .touchDragExit)
         sender.addTarget(self, action: #selector(buttonTouchDragEnter(_:)), for: .touchDragEnter)
         sender.addTarget(self, action: #selector(buttonTouchCancel(_:)), for: .touchCancel)

        // Logic for starting game
        switch sender {
           case startEasyAIButton: startGame(mode: .humanVsAI, difficulty: .easy)
           case startMediumAIButton: startGame(mode: .humanVsAI, difficulty: .medium)
           case startHardAIButton: startGame(mode: .humanVsAI, difficulty: .hard)
           case startHvsHButton: startGame(mode: .humanVsHuman, difficulty: .easy)
           default: print("Unknown setup button tapped")
        }
    }

    @objc func didTapGameOverButton(_ sender: UIButton) {
        animateButtonUp(sender) // Animate up on release inside
        impactFeedbackGenerator.impactOccurred()
         // Add touch down event to trigger down animation
         sender.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
         sender.addTarget(self, action: #selector(buttonTouchDragExit(_:)), for: .touchDragExit)
         sender.addTarget(self, action: #selector(buttonTouchDragEnter(_:)), for: .touchDragEnter)
         sender.addTarget(self, action: #selector(buttonTouchCancel(_:)), for: .touchCancel)

        // Logic for game over actions
        switch sender {
            case playAgainButton:
                 hideGameOverOverlay()
                 startGame(mode: currentGameMode, difficulty: selectedDifficulty)
            case overlayMainMenuButton:
                 hideGameOverOverlay()
                 showSetupUI()
            default: print("Unknown game over button tapped")
        }
    }

    @objc func didTapMenuButton(_ sender: UIButton) {
        animateButtonUp(sender) // Animate up on release inside
        impactFeedbackGenerator.impactOccurred()
         // Add touch down event to trigger down animation
         sender.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
         sender.addTarget(self, action: #selector(buttonTouchDragExit(_:)), for: .touchDragExit)
         sender.addTarget(self, action: #selector(buttonTouchDragEnter(_:)), for: .touchDragEnter)
         sender.addTarget(self, action: #selector(buttonTouchCancel(_:)), for: .touchCancel)

        // Logic for menu action
        hideGameOverOverlay()
        showSetupUI()
    }

    // --- NEW: Generic Button Touch Down/Up Actions ---
     @objc private func buttonTouchDown(_ sender: UIButton) {
         animateButtonDown(sender)
     }

     // Handle dragging finger off the button
     @objc private func buttonTouchDragExit(_ sender: UIButton) {
         animateButtonUp(sender) // Reset if finger leaves
     }
     // Handle dragging finger back onto the button
      @objc private func buttonTouchDragEnter(_ sender: UIButton) {
          animateButtonDown(sender) // Press down again if finger re-enters
      }
      // Handle touch cancellation (e.g., system interruption)
       @objc private func buttonTouchCancel(_ sender: UIButton) {
           animateButtonUp(sender) // Reset on cancel
       }

    func startGame(mode: GameMode, difficulty: AIDifficulty) {
        // ... (Keep existing startGame logic) ...
         print("Starting game mode: \(mode), Difficulty: \(difficulty)");
         self.currentGameMode = mode;
         self.selectedDifficulty = (mode == .humanVsAI) ? difficulty : .easy
         showGameUI();
         setupNewGame();
         view.setNeedsLayout()
         view.layoutIfNeeded()
         print("Game started.")
         if isAiTurn && !gameOver {
             view.isUserInteractionEnabled = false
             statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."
             print("AI (\(selectedDifficulty)) starts first.")
             DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in self?.performAiTurn() }
         }
    }

    // --- Styling Functions ---
    // --- NEW: Move Count Label Setup ---
    func createMoveCountLabel() {
        moveCountLabel.translatesAutoresizingMaskIntoConstraints = false
        moveCountLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        moveCountLabel.textColor = UIColor.darkGray.withAlphaComponent(0.7)
        moveCountLabel.textAlignment = .right
        moveCountLabel.text = "Moves: 0"
        moveCountLabel.isHidden = true // Start hidden
        view.addSubview(moveCountLabel)
        print("Move count label created.")
    }

    func setupMoveCountLabelConstraints() {
        // Ensure constraints are only added once
        guard !self.view.constraints.contains(where: { $0.firstItem === moveCountLabel || $0.secondItem === moveCountLabel }) else { return }

        print("Setting up Move Count Label constraints...")
        let safeArea = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            moveCountLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8), // Below status label
            moveCountLabel.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor, constant: -20) // Top-rightish area
        ])
        print("Move Count Label constraints activated.")
    }
    
    func setupMainBackground() { /* ... */ backgroundGradientLayer?.removeFromSuperlayer(); let gradient = CAGradientLayer(); gradient.frame = self.view.bounds; let topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor; let bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor; gradient.colors = [topColor, bottomColor]; gradient.startPoint = CGPoint(x: 0.5, y: 0.0); gradient.endPoint = CGPoint(x: 0.5, y: 1.0); self.view.layer.insertSublayer(gradient, at: 0); self.backgroundGradientLayer = gradient }
    func styleResetButton() { /* ... */ guard let button = resetButton else { return }; print("Styling Reset Button (V3 - with Icon)..."); if #available(iOS 15.0, *) { var config = UIButton.Configuration.filled(); config.title = "Reset Game"; config.attributedTitle?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); config.image = UIImage(systemName: "arrow.counterclockwise.circle"); config.imagePadding = 8; config.imagePlacement = .leading; config.baseBackgroundColor = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0); config.baseForegroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0); config.cornerStyle = .medium; config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18); button.configuration = config; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false } else { let buttonBackgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0); let buttonTextColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0); let buttonBorderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8); button.backgroundColor = buttonBackgroundColor; button.setTitleColor(buttonTextColor, for: .normal); button.setTitleColor(buttonTextColor.withAlphaComponent(0.5), for: .highlighted); button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); button.layer.cornerRadius = 8; button.layer.borderWidth = 0.75; button.layer.borderColor = buttonBorderColor.cgColor; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20) }; print("Reset Button styling applied (V3).") }
    func styleStatusLabel() { /* ... */ guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center; label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false }

    // --- Drawing Functions ---
    func drawProceduralWoodBackground() {
        /* ... */
        woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll()
        guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }
        print("Drawing procedural wood background into bounds: \(boardView.bounds)")
        let baseLayer = CALayer()
        baseLayer.frame = boardView.bounds
        baseLayer.backgroundColor = UIColor(red: 0.65, green: 0.50, blue: 0.35, alpha: 1.0).cgColor
        baseLayer.cornerRadius = boardView.layer.cornerRadius // Use boardView's radius
        baseLayer.masksToBounds = true // <-- IMPORTANT: Clip the wood layer
        boardView.layer.insertSublayer(baseLayer, at: 0)
        woodBackgroundLayers.append(baseLayer)
        let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height; for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.10...0.15); let baseRed: CGFloat = 0.65; let baseGreen: CGFloat = 0.50; let baseBlue: CGFloat = 0.35; let grainColor = UIColor(red: max(0.1, min(0.9, baseRed + randomDarkness)), green: max(0.1, min(0.9, baseGreen + randomDarkness)), blue: max(0.1, min(0.9, baseBlue + randomDarkness)), alpha: CGFloat.random(in: 0.1...0.35)); grainLayer.backgroundColor = grainColor.cgColor; let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }; let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; lightingGradient.startPoint = CGPoint(x: 0.5, y: 0.5); lightingGradient.endPoint = CGPoint(x: 1.0, y: 1.0); baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 2.0; baseLayer.borderColor = UIColor(white: 0.1, alpha: 0.8).cgColor }
    func drawBoard() { /* ... */ boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }; guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }; let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(white: 0.1, alpha: 0.65).cgColor; let gridLineWidth: CGFloat = 0.75; for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }; print("Board drawn with cell size: \(cellSize)") }
    func redrawPieces() { /* ... */ guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }; boardView.subviews.forEach { $0.removeFromSuperview() }; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white, animate: false) }}} }
    func drawPiece(atRow row: Int, col: Int, player: Player, animate: Bool = true) { /* ... */ guard cellSize > 0 else { return }; let pieceSize = cellSize * 0.85; let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2); let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2); let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize); let pieceView = UIView(frame: pieceFrame); pieceView.backgroundColor = .clear; let gradientLayer = CAGradientLayer(); gradientLayer.frame = pieceView.bounds; gradientLayer.cornerRadius = pieceSize / 2; gradientLayer.type = .radial; let lightColor: UIColor; let darkColor: UIColor; let highlightColor: UIColor; if player == .black { highlightColor = UIColor(white: 0.5, alpha: 1.0); lightColor = UIColor(white: 0.3, alpha: 1.0); darkColor = UIColor(white: 0.05, alpha: 1.0) } else { highlightColor = UIColor(white: 1.0, alpha: 1.0); lightColor = UIColor(white: 0.95, alpha: 1.0); darkColor = UIColor(white: 0.75, alpha: 1.0) }; gradientLayer.colors = [highlightColor.cgColor, lightColor.cgColor, darkColor.cgColor]; gradientLayer.locations = [0.0, 0.15, 1.0]; gradientLayer.startPoint = CGPoint(x: 0.25, y: 0.25); gradientLayer.endPoint = CGPoint(x: 0.75, y: 0.75); pieceView.layer.addSublayer(gradientLayer); pieceView.layer.cornerRadius = pieceSize / 2; pieceView.layer.borderWidth = 0.5; pieceView.layer.borderColor = (player == .black) ? UIColor(white: 0.5, alpha: 0.7).cgColor : UIColor(white: 0.6, alpha: 0.7).cgColor; pieceView.layer.shadowColor = UIColor.black.cgColor; pieceView.layer.shadowOpacity = 0.4; pieceView.layer.shadowOffset = CGSize(width: 1, height: 2); pieceView.layer.shadowRadius = 2.0; pieceView.layer.masksToBounds = false; pieceViews[row][col]?.removeFromSuperview(); boardView.addSubview(pieceView); pieceViews[row][col] = pieceView; if animate { pieceView.alpha = 0.0; pieceView.transform = CGAffineTransform(scaleX: 0.6, y: 0.6); UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: { pieceView.alpha = 1.0; pieceView.transform = .identity }, completion: nil) } else { pieceView.alpha = 1.0; pieceView.transform = .identity } }
    func showLastMoveIndicator(at position: Position) { /* ... */ lastMoveIndicatorLayer?.removeFromSuperlayer(); lastMoveIndicatorLayer = nil; guard cellSize > 0, !gameOver else { return }; let indicatorSize = cellSize * 0.95; let x = boardPadding + CGFloat(position.col) * cellSize - (indicatorSize / 2); let y = boardPadding + CGFloat(position.row) * cellSize - (indicatorSize / 2); let indicatorFrame = CGRect(x: x, y: y, width: indicatorSize, height: indicatorSize); let indicator = CALayer(); indicator.frame = indicatorFrame; indicator.cornerRadius = indicatorSize / 2; indicator.borderWidth = 2.5; indicator.borderColor = UIColor.systemYellow.withAlphaComponent(0.8).cgColor; indicator.opacity = 0.0; indicator.name = "lastMoveIndicator"; boardView.layer.addSublayer(indicator); self.lastMoveIndicatorLayer = indicator; let fadeIn = CABasicAnimation(keyPath: "opacity"); fadeIn.fromValue = 0.0; fadeIn.toValue = 0.8; fadeIn.duration = 0.2; indicator.opacity = 0.8; indicator.add(fadeIn, forKey: "fadeInIndicator") }

    // --- Game Logic & Interaction ---
    func setupNewGameVariablesOnly() { /* ... */ currentPlayer = .black; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); gameOver = false; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); lastWinningPositions = nil }
    func setupNewGame() { /* ... ADDED RESETcellSize/Bounds */ print("setupNewGame called. Current Mode: \(currentGameMode)"); gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); boardView.subviews.forEach { $0.removeFromSuperview() }; boardView.layer.sublayers?.filter { $0.name == "gridLine" || $0.name == "winningLine" || $0.name == "lastMoveIndicator"}.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll(); winningLineLayer = nil; lastMoveIndicatorLayer = nil; lastMovePosition = nil; lastWinningPositions = nil; moveCount = 0; moveCountLabel.text = "Moves: 0"; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); cellSize = 0; lastDrawnBoardBounds = .zero; updateTurnIndicatorLine(); turnIndicatorView?.isHidden = false; print("setupNewGame: Reset game state. Requesting layout update."); view.setNeedsLayout() }
    func calculateCellSize() -> CGFloat { /* ... */ guard boardView.bounds.width > 0, boardView.bounds.height > 0 else { return 0 }; let boardDimension = min(boardView.bounds.width, boardView.bounds.height) - (boardPadding * 2); guard boardSize > 1 else { return boardDimension }; let size = boardDimension / CGFloat(boardSize - 1); return max(0, size) }
    func addTapGestureRecognizer() { /* ... */ guard let currentBoardView = boardView else { print("FATAL ERROR: boardView outlet is NIL..."); return }; currentBoardView.gestureRecognizers?.forEach { currentBoardView.removeGestureRecognizer($0) }; let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))); currentBoardView.addGestureRecognizer(tap); }
    
    func shakeBoard() {
        print("Shaking board for invalid move")
        // --- ADDED Sound & Haptic ---
        playSound(key: "invalid")
        notificationFeedbackGenerator.notificationOccurred(.warning)
        
        if shakeAnimation == nil {
            let animation = CABasicAnimation(keyPath: "position.x"); animation.duration = 0.07; animation.repeatCount = 3; animation.autoreverses = true; animation.fromValue = NSNumber(value: boardView.center.x - CGFloat(6)); animation.toValue = NSNumber(value: boardView.center.x + CGFloat(6)); shakeAnimation = animation
        }
        if let shake = shakeAnimation, boardView != nil { boardView.layer.add(shake, forKey: "position.x") }
        else if boardView == nil { print("Warning: Tried to shake boardView but it was nil.") }
    }
    
    @objc func handleTap(_ sender: UITapGestureRecognizer) {
        guard currentGameState == .playing else { return }
        guard !gameOver, cellSize > 0 else { return }
        guard !isAiTurn else { print("Tap ignored: It's AI's turn."); return }

        let location = sender.location(in: boardView)
        let playableWidth = cellSize * CGFloat(boardSize - 1); let playableHeight = cellSize * CGFloat(boardSize - 1)
        let tapArea = CGRect(x: boardPadding - cellSize * 0.5, y: boardPadding - cellSize * 0.5,
                             width: playableWidth + cellSize, height: playableHeight + cellSize)

        guard tapArea.contains(location) else {
            print("Tap outside playable area.")
            shakeBoard()
            return
        }

        let tappedColFloat = (location.x - boardPadding + cellSize * 0.5) / cellSize
        let tappedRowFloat = (location.y - boardPadding + cellSize * 0.5) / cellSize
        let tappedCol = Int(floor(tappedColFloat))
        let tappedRow = Int(floor(tappedRowFloat))

        guard checkBounds(row: tappedRow, col: tappedCol) else {
            print("Tap out of bounds.")
            shakeBoard()
            return
        }
        guard board[tappedRow][tappedCol] == .empty else {
            print("Cell already occupied.")
            shakeBoard()
            return
        }

        // --- FIX: Trigger Sound & Haptic HERE ---
        playSound(key: "place")
        impactFeedbackGenerator.impactOccurred()
        // ----------------------------------------

        print("Human placing piece at (\(tappedRow), \(tappedCol))");
        // Now call placePiece, which will handle game logic and drawing
        placePiece(atRow: tappedRow, col: tappedCol)
    }
    
    func placePiece(atRow row: Int, col: Int) {
        guard currentGameState == .playing, !gameOver else { return }
        guard checkBounds(row: row, col: col) && board[row][col] == .empty else {
             print("Error: Attempted to place piece in invalid or occupied cell (\(row), \(col)). Current state: \(board[row][col])")
             if isAiTurn { print("!!! AI ERROR: AI attempted invalid move. Halting AI turn. !!!"); view.isUserInteractionEnabled = true }
             return
        }

        // --- Increment and Update Move Count ---
        moveCount += 1
        moveCountLabel.text = "Moves: \(moveCount)"
        
        let piecePlayer = currentPlayer // Store who is making this move
        let pieceState: CellState = state(for: piecePlayer)
        board[row][col] = pieceState
        drawPiece(atRow: row, col: col, player: piecePlayer, animate: true) // Piece placed visually

        let currentPosition = Position(row: row, col: col)
        self.lastMovePosition = currentPosition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showLastMoveIndicator(at: currentPosition) }

        if let winningPositions = findWinningLine(playerState: pieceState, lastRow: row, lastCol: col) {
            gameOver = true; self.lastWinningPositions = winningPositions
            updateTurnIndicatorLine()
            let winnerName = (pieceState == .black) ? "Black" : "White"; let message = "\(winnerName) Wins!"
            statusLabel.text = message; print(message)

            // --- FIX: Differentiate sound/haptic based on who won ---
            if piecePlayer == aiPlayer {
                // AI Wins (Human Loses)
                print("AI Wins. Playing lose sound.")
                playSound(key: "lose")
                notificationFeedbackGenerator.notificationOccurred(.error) // Use error haptic for loss
            } else {
                // Human Wins
                print("Human Wins. Playing win sound.")
                playSound(key: "win")
                notificationFeedbackGenerator.notificationOccurred(.success)
            }
            // --- End Fix ---

            drawWinningLine(positions: winningPositions) // Draw line & highlight pieces
            showGameOverOverlay(message: message); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer()
            lastMoveIndicatorLayer = nil

        } else if isBoardFull() {
            gameOver = true; updateTurnIndicatorLine()
            statusLabel.text = "Draw!"; print("Draw!")

            // --- Draw Sound & Haptic (No change needed here) ---
            playSound(key: "lose") // Use lose sound for draw
            notificationFeedbackGenerator.notificationOccurred(.error) // Use error haptic for draw/loss

            showGameOverOverlay(message: "Draw!"); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer()
            lastMoveIndicatorLayer = nil

        } else {
            switchPlayer() // Only switch if game not over
        }
    }

    
    func findWinningLine(playerState: CellState, lastRow: Int, lastCol: Int) -> [Position]? { /* ... */ guard playerState != .empty else { return nil }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var linePositions: [Position] = [Position(row: lastRow, col: lastCol)]; var count = 1; for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }; for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }; if count >= 5 { linePositions.sort { ($0.row, $0.col) < ($1.row, $1.col) }; return Array(linePositions) } }; return nil }
    func switchPlayer() { /* ... */ guard !gameOver else { return }; currentPlayer = (currentPlayer == .black) ? .white : .black; statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"; updateTurnIndicatorLine(); if isAiTurn { view.isUserInteractionEnabled = false; statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."; print("Switching to AI (\(selectedDifficulty)) turn..."); let delay = (selectedDifficulty == .hard) ? 0.6 : 0.4; DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in guard let self = self else { return }; if !self.gameOver && self.isAiTurn { self.performAiTurn() } else { print("AI turn skipped (game over or state changed during delay)"); if !self.gameOver { self.view.isUserInteractionEnabled = true } } } } else { print("Switching to Human turn..."); view.isUserInteractionEnabled = true } }

    // --- AI Logic (performAiTurn, performSimpleAiMove, performStandardAiMove, performHardAiMove, helpers) ---
    // --- NEW: Helper specifically for Medium AI's Open Three detection ---
    func findSpecificOpenThreeMoves(for player: Player, on boardToCheck: [[CellState]], availableMoves: [Position]) -> [Position] {
        let playerState = state(for: player)
        var openThreeMoves: [Position] = []
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)] // Horizontal, Vertical, Diag Down, Diag Up

        for position in availableMoves {
            // Check if placing a piece HERE creates an open three
            // Pattern: .Empty, Player, Player, Player, .Empty
            for (dr, dc) in directions {
                // Check E P P P E centered on position (P P P E starts 1 before, E P P starts 2 before)
                let patternsToCheck: [[CellState?]] = [
                    // . E P P P E (position is the E)
                    [nil, playerState, playerState, playerState, .empty],
                    // E . P P P E (position is the .)
                    [.empty, nil, playerState, playerState, .empty],
                    // E P . P P E (position is the .)
                    [.empty, playerState, nil, playerState, .empty],
                    // E P P . P E (position is the .)
                    [.empty, playerState, playerState, nil, .empty],
                    // E P P P . E (position is the .)
                    [.empty, playerState, playerState, playerState, nil]
                ]

                for patternOffset in 0..<patternsToCheck.count {
                    let pattern = patternsToCheck[patternOffset]
                    let startOffset = -patternOffset // How far back from 'position' the pattern starts

                    // Check bounds for the whole 6-cell pattern window (_ E P P P E _)
                    let checkR_Start = position.row + dr * (startOffset - 1)
                    let checkC_Start = position.col + dc * (startOffset - 1)
                    let checkR_End = position.row + dr * (startOffset + 5)
                    let checkC_End = position.col + dc * (startOffset + 5)

                    guard checkBounds(row: checkR_Start, col: checkC_Start) && checkBounds(row: checkR_End, col: checkC_End) else { continue }

                    // Check the actual pattern, ensuring the spaces are exactly EMPTY
                    var matches = true
                    if boardToCheck[checkR_Start][checkC_Start] != .empty { matches = false; break } // Must be empty before
                    if boardToCheck[checkR_End][checkC_End] != .empty { matches = false; break }     // Must be empty after

                    for i in 0..<5 {
                        let currentR = position.row + dr * (startOffset + i)
                        let currentC = position.col + dc * (startOffset + i)
                        // Use the pattern definition, nil means it should be the currently checked 'position'
                        let expectedState = (pattern[i] == nil) ? playerState : pattern[i]

                        if boardToCheck[currentR][currentC] != expectedState {
                            matches = false
                            break
                        }
                    }

                    if matches {
                        openThreeMoves.append(position)
                        // Go to next direction once found for this position
                        // (avoids adding the same position multiple times if it makes multiple threes)
                        // Note: Or allow multiple additions if we want to prioritize multi-threat moves later?
                        // For Medium, just finding one is enough.
                        break // Go to next direction
                    }
                } // End patternOffset loop
                 if openThreeMoves.contains(position) { break } // Go to next position if already added
            } // End directions loop
        } // End position loop

        return Array(Set(openThreeMoves)) // Return unique positions
    }
    // Function to find empty cells where placing a piece *creates* the specified threat
    // (This function definition should already be present from the Minimax version)
    func findMovesCreatingThreat(player: Player, threat: ThreatType, emptyCells: [Position]) -> [Position] {
        var threatMoves: [Position] = []
        for position in emptyCells {
            var tempBoard = self.board // Use the ACTUAL current board state as the base
            // Only proceed if the cell is actually empty on the real board
            guard tempBoard[position.row][position.col] == .empty else { continue }
            
            tempBoard[position.row][position.col] = state(for: player) // Place piece hypothetically

            // Check if THIS move created the specified threat originating from 'position'
            if checkForThreatOnBoard(boardToCheck: tempBoard, player: player, threat: threat, lastMove: position) {
                 threatMoves.append(position)
            }
        }
        return threatMoves
    }

    // Checks the board *after* a move has been made at lastMove for the specified threat type involving that last move
    // (This function definition should also be present from the Minimax version)
    func checkForThreatOnBoard(boardToCheck: [[CellState]], player: Player, threat: ThreatType, lastMove: Position) -> Bool {
        let playerState = state(for: player)
        let opponentState = state(for: opponent(of: player))
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)] // Horizontal, Vertical, Diag Down, Diag Up

        for (dr, dc) in directions {
            // FIVE: Check existing win condition checker (already handles this)
            if threat == .five {
                 if checkForWinOnBoard(boardToCheck: boardToCheck, playerState: playerState, lastRow: lastMove.row, lastCol: lastMove.col) {
                     return true
                 }
                 continue // Check next direction for five
            }

            // OPEN FOUR (Check window 6: E P P P P E)
            if threat == .openFour {
                 // Check patterns where lastMove is one of the four P's
                 for offset in -4...0 { // Sliding window start relative to the move that formed the four
                    let r_windowStart = lastMove.row + dr * offset
                    let c_windowStart = lastMove.col + dc * offset
                    
                    // Ensure the 6-cell window (_ P P P P _) is in bounds
                    guard checkBounds(row: r_windowStart - dr, col: c_windowStart - dc) &&
                          checkBounds(row: r_windowStart + dr * 5, col: c_windowStart + dc * 5) else { continue }

                    // Check the pattern _ P P P P _
                    if boardToCheck[r_windowStart - dr][c_windowStart - dc] == .empty &&     // Before is empty
                       boardToCheck[r_windowStart][c_windowStart] == playerState &&         // P
                       boardToCheck[r_windowStart + dr][c_windowStart + dc] == playerState && // P
                       boardToCheck[r_windowStart + dr * 2][c_windowStart + dc * 2] == playerState && // P
                       boardToCheck[r_windowStart + dr * 3][c_windowStart + dc * 3] == playerState && // P
                       boardToCheck[r_windowStart + dr * 4][c_windowStart + dc * 4] == .empty {    // After is empty
                         return true // Found Open Four
                    }
                 }
            } // End Open Four Check

            // CLOSED FOUR, OPEN THREE, CLOSED THREE (Check window 5 and context)
            if threat == .closedFour || threat == .openThree || threat == .closedThree {
                // Check patterns where lastMove is one of the relevant P's or the E in a closed four
                 for offset in -4...0 { // Check 5-windows containing the new piece
                     let r = lastMove.row + dr * offset
                     let c = lastMove.col + dc * offset
                     // Check bounds for the 5-window
                     guard checkBounds(row: r, col: c) && checkBounds(row: r + dr * 4, col: c + dc * 4) else { continue }

                     var pCount = 0
                     var eCount = 0
                     var oCount = 0 // Opponent count within window
                     for i in 0..<5 {
                          let cellState = boardToCheck[r+dr*i][c+dc*i]
                          if cellState == playerState { pCount += 1 }
                          else if cellState == .empty { eCount += 1 }
                          else { oCount += 1} // Opponent piece
                     }
                     
                     // If opponent piece is within the 5-window, it cannot be these threats for 'player'
                     if oCount > 0 { continue }

                     // Check context cells (before start, after end)
                     let rBefore = r - dr
                     let cBefore = c - dc
                     let rAfter = r + dr * 5
                     let cAfter = c + dc * 5

                     let stateBefore = checkBounds(row: rBefore, col: cBefore) ? boardToCheck[rBefore][cBefore] : opponentState
                     let stateAfter = checkBounds(row: rAfter, col: cAfter) ? boardToCheck[rAfter][cAfter] : opponentState

                     let isOpenBefore = stateBefore == .empty
                     let isOpenAfter = stateAfter == .empty
                     let isBlockedBefore = !isOpenBefore
                     let isBlockedAfter = !isOpenAfter

                     // --- Match Threat Type ---
                     // Closed Four: PPPP_ or _PPPP with one side blocked, other empty
                     if threat == .closedFour && pCount == 4 && eCount == 1 {
                          if (isBlockedBefore && isOpenAfter) || (isOpenBefore && isBlockedAfter) {
                              return true
                          }
                     // Open Three: _PPP_ with both sides open
                     } else if threat == .openThree && pCount == 3 && eCount == 2 {
                          if isOpenBefore && isOpenAfter {
                              return true
                          }
                      // Closed Three: _PPP_ with one side blocked, one open
                     } else if threat == .closedThree && pCount == 3 && eCount == 2 {
                          if (isBlockedBefore && isOpenAfter) || (isOpenBefore && isBlockedAfter) {
                              return true
                          }
                     }
                 } // End 5-window offset loop
            } // End if check threes/closed four
        } // End directions loop

        return false // No threat of the specified type found involving the last move
    }
    
    // Checks if placing 'player' at 'position' would *result* in an Open Three formation
    // (Re-paste this function if you removed it)
    func checkPotentialOpenThree(player: Player, position: Position, on boardToCheck: [[CellState]]) -> Bool {
        guard boardToCheck[position.row][position.col] == .empty else { return false } // Pre-condition

        var tempBoard = boardToCheck
        tempBoard[position.row][position.col] = state(for: player) // Simulate the move
        let playerState = state(for: player)
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

        // Basic pattern check for _PPP_ centered around the new piece
        // This checks if the piece completes the sequence
        for (dr, dc) in directions {
            // Check _ P P P _ where position is the first P
            if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty],
                            startRow: position.row - dr, startCol: position.col - dc,
                            direction: (dr, dc), on: tempBoard) { return true }
            // Check _ P P P _ where position is the second P
            if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty],
                            startRow: position.row - dr*2, startCol: position.col - dc*2,
                            direction: (dr, dc), on: tempBoard) { return true }
            // Check _ P P P _ where position is the third P
            if checkPattern(pattern: [.empty, playerState, playerState, playerState, .empty],
                            startRow: position.row - dr*3, startCol: position.col - dc*3,
                            direction: (dr, dc), on: tempBoard) { return true }
        }
        return false
    }
    
    // --- NEW: Helper to check if a move creates a Four-in-a-row ---
    func checkPotentialFour(player: Player, position: Position, on boardToCheck: [[CellState]]) -> Bool {
        // Ensure the position is empty before simulating
        guard checkBounds(row: position.row, col: position.col) && boardToCheck[position.row][position.col] == .empty else { return false }

        var tempBoard = boardToCheck
        tempBoard[position.row][position.col] = state(for: player) // Simulate the move
        let playerState = state(for: player)
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

        // Check around the placed piece 'position'
        for (dr, dc) in directions {
            var count = 1 // Count includes the piece at 'position'
            // Count in positive direction
            for i in 1..<4 { // Check up to 3 more stones
                let r = position.row + dr * i
                let c = position.col + dc * i
                if checkBounds(row: r, col: c) && tempBoard[r][c] == playerState {
                    count += 1
                } else {
                    break
                }
            }
            // Count in negative direction
            for i in 1..<4 { // Check up to 3 more stones
                let r = position.row - dr * i
                let c = position.col - dc * i
                if checkBounds(row: r, col: c) && tempBoard[r][c] == playerState {
                    count += 1
                } else {
                    break
                }
            }
            // If we found exactly 4, it's a four-threat created by this move
            if count == 4 {
                 // Optional: Add checks here to distinguish open/closed fours if needed later,
                 // but for blocking, just finding any four is critical for Medium.
                 return true
            }
        }
        return false // No four-in-a-row created by this move
    }

    // Ensure you also have the checkPattern helper:
    func checkPattern(pattern: [CellState], startRow: Int, startCol: Int, direction: (dr: Int, dc: Int), on boardToCheck: [[CellState]]) -> Bool {
        for i in 0..<pattern.count {
            let r = startRow + direction.dr * i
            let c = startCol + direction.dc * i
            guard checkBounds(row: r, col: c) else { return false }
            if boardToCheck[r][c] != pattern[i] { return false }
        }
        return true
    }

    // ... (Keep all existing AI logic from the previous step unchanged) ...
     func performAiTurn() { guard !gameOver else { view.isUserInteractionEnabled = true; return }; print("AI Turn (\(selectedDifficulty)): Performing move..."); let startTime = CFAbsoluteTimeGetCurrent(); switch selectedDifficulty { case .easy: performSimpleAiMove(); case .medium: performStandardAiMove(); case .hard: performHardAiMove() }; let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime; print("AI (\(selectedDifficulty)) took \(String(format: "%.3f", timeElapsed)) seconds."); DispatchQueue.main.async { if !self.gameOver && !self.isAiTurn { self.view.isUserInteractionEnabled = true; self.statusLabel.text = "\(self.currentPlayer == .black ? "Black" : "White")'s Turn"; print("AI Turn (\(self.selectedDifficulty)): Completed. Re-enabled user interaction.") } else if self.gameOver { print("AI Turn (\(self.selectedDifficulty)): Game Over.") } else { print("AI Turn (\(self.selectedDifficulty)): Completed, still AI turn? (AI vs AI?)") } } }
    // --- REVISED: Easy AI Logic ---
    // --- REVISED: Easy AI Logic (with probabilistic Open Three block) ---
    func performSimpleAiMove() {
        let emptyCells = findEmptyCells(on: self.board)
        if emptyCells.isEmpty { print("AI Easy: No empty cells left."); return }
        let humanPlayer: Player = opponent(of: aiPlayer)

        // Priority 1: Win?
        for cell in emptyCells {
            if checkPotentialWin(player: aiPlayer, position: cell) {
                print("AI Easy: Found winning move at \(cell)")
                placeAiPieceAndEndTurn(at: cell); return
            }
        }

        // Priority 2: Block Win?
        for cell in emptyCells {
            if checkPotentialWin(player: humanPlayer, position: cell) {
                print("AI Easy: Found blocking win move at \(cell)")
                placeAiPieceAndEndTurn(at: cell); return
            }
        }

        // --- NEW Priority 3: Probabilistic Block Opponent's Open Three ---
        var humanOpenThreeBlockingMoves: [Position] = []
        for cell in emptyCells {
            // Check if HUMAN playing at 'cell' creates an Open Three
            if checkPotentialOpenThree(player: humanPlayer, position: cell, on: self.board) {
                humanOpenThreeBlockingMoves.append(cell) // Add the cell AI needs to play at to block
            }
        }

        if !humanOpenThreeBlockingMoves.isEmpty {
            // Make Easy AI block only sometimes (e.g., 70% chance)
            let shouldBlock = Int.random(in: 0..<100) < 70 // 70% chance to block
            if shouldBlock, let blockMove = humanOpenThreeBlockingMoves.randomElement() {
                print("AI Easy: Decided to block opponent's potential Open Three at \(blockMove)")
                placeAiPieceAndEndTurn(at: blockMove); return
            } else if !shouldBlock {
                 print("AI Easy: Found opponent Open Three threat but decided not to block (probability).")
                 // If not blocking, fall through to adjacent/first empty logic
            }
        }
        // --- End NEW Priority ---


        // Priority 4: Play adjacent to any existing piece? (Was P3)
        let adjacentCells = findAdjacentEmptyCells(on: self.board)
        if let targetCell = adjacentCells.randomElement() {
            print("AI Easy: Playing random adjacent move at \(targetCell)")
            placeAiPieceAndEndTurn(at: targetCell); return
        }

        // Priority 5: Play the *first* available empty cell (deterministic fallback) (Was P4)
        if let firstEmpty = emptyCells.first {
             print("AI Easy: No adjacent moves found. Playing first available empty cell at \(firstEmpty).")
             placeAiPieceAndEndTurn(at: firstEmpty)
             return
        }

        // Should be unreachable
        print("AI Easy: Could not find any valid move.")
    }
    // --- REVISED: Medium AI Logic ---
    func performStandardAiMove() {
        let emptyCells = findEmptyCells(on: self.board)
        if emptyCells.isEmpty { print("AI Medium: No empty cells left."); return }
        let humanPlayer: Player = opponent(of: aiPlayer)

        // Priority 1: Win?
        if let winMove = findMovesCreatingThreat(player: aiPlayer, threat: .five, emptyCells: emptyCells).first {
            print("AI Medium: Found winning move at \(winMove)")
            placeAiPieceAndEndTurn(at: winMove); return
        }

        // Priority 2: Block Win?
        if let blockWinMove = findMovesCreatingThreat(player: humanPlayer, threat: .five, emptyCells: emptyCells).first {
            print("AI Medium: Found blocking win move at \(blockWinMove)")
            placeAiPieceAndEndTurn(at: blockWinMove); return
        }

        // --- NEW Priority 3: Block Opponent's Four-in-a-row Threat ---
        var humanFourThreatBlocks: [Position] = []
        for cell in emptyCells {
            // Check if HUMAN playing at 'cell' would create a Four
            if checkPotentialFour(player: humanPlayer, position: cell, on: self.board) {
                humanFourThreatBlocks.append(cell) // Add the cell AI needs to play at to block
            }
        }
        if let blockFourMove = humanFourThreatBlocks.randomElement() { // Block one if multiple exist
            print("AI Medium: Found blocking opponent's potential Four-in-a-row at \(blockFourMove)")
            placeAiPieceAndEndTurn(at: blockFourMove); return
        }
        // --- End NEW Priority ---


        // Priority 4: Create an Open Three for AI? (Was Priority 3)
        var aiOpenThreeMoves: [Position] = []
        for cell in emptyCells {
            if checkPotentialOpenThree(player: aiPlayer, position: cell, on: self.board) {
                aiOpenThreeMoves.append(cell)
            }
        }
        if let createMove = aiOpenThreeMoves.randomElement() {
            print("AI Medium: Found creating Open Three move at \(createMove)")
            placeAiPieceAndEndTurn(at: createMove); return
        }

        // Priority 5: Block an Open Three for Human? (Was Priority 4)
        var humanOpenThreeBlockingMoves: [Position] = []
        for cell in emptyCells {
            if checkPotentialOpenThree(player: humanPlayer, position: cell, on: self.board) {
                humanOpenThreeBlockingMoves.append(cell)
            }
        }
        if let blockThreeMove = humanOpenThreeBlockingMoves.randomElement() {
            print("AI Medium: Found blocking opponent's potential Open Three at \(blockThreeMove)")
            placeAiPieceAndEndTurn(at: blockThreeMove); return
        }

        // --- Fallback Logic ---
        // Priority 6: Play adjacent to any existing piece? (Was P5)
        let adjacentCells = findAdjacentEmptyCells(on: self.board)
        if let targetCell = adjacentCells.randomElement() {
            print("AI Medium: No threats found. Playing random adjacent move at \(targetCell)")
            placeAiPieceAndEndTurn(at: targetCell); return
        }

        // Priority 7: Play the *first* available empty cell (Was P6)
        if let firstEmpty = emptyCells.first {
             print("AI Medium: No adjacent moves found. Playing first available empty cell at \(firstEmpty).")
             placeAiPieceAndEndTurn(at: firstEmpty)
             return
        }

        // Should be unreachable
        print("AI Medium: Could not find any valid move.")
    }
    // --- REVISED HARD AI LOGIC (Uses Minimax) ---
    func performHardAiMove() {
        let emptyCells = findEmptyCells(on: self.board)
        guard !emptyCells.isEmpty else { print("AI Hard (Minimax): No empty cells left."); return }

        let humanPlayer = opponent(of: aiPlayer)

        // --- Immediate Win/Loss Check (Optimization) ---
        // Check if AI can win immediately
        for cell in emptyCells {
            if checkPotentialWin(player: aiPlayer, position: cell) {
                print("AI Hard (Minimax): Found immediate winning move at \(cell)")
                placeAiPieceAndEndTurn(at: cell); return
            }
        }
        // Check if Human can win immediately (must block)
        var blockingMoves: [Position] = []
        for cell in emptyCells {
            if checkPotentialWin(player: humanPlayer, position: cell) {
                blockingMoves.append(cell)
            }
        }
        if let blockMove = blockingMoves.first { // Usually only one immediate threat
            print("AI Hard (Minimax): Found immediate blocking move at \(blockMove)")
            placeAiPieceAndEndTurn(at: blockMove); return
        }
        // --- End Immediate Checks ---


        // --- Handle first move(s) for better opening ---
        let totalPieces = board.flatMap({ $0 }).filter({ $0 != .empty }).count
        if totalPieces < 2 {
            let center = boardSize / 2
            let move = Position(row: center, col: center)
            if checkBounds(row: center, col: center) && board[center][center] == .empty {
                print("AI Hard (Minimax): First move, playing center.")
                placeAiPieceAndEndTurn(at: move)
                return
            } else {
                 // If center taken, play adjacent (simple fallback for now)
                 if let adjacentMove = findAdjacentEmptyCells(on: self.board).randomElement() {
                     print("AI Hard (Minimax): First move, center taken, playing adjacent.")
                     placeAiPieceAndEndTurn(at: adjacentMove)
                     return
                 }
            }
        }

        print("AI Hard (Minimax): Evaluating moves with depth \(MAX_DEPTH)...")

        // --- Find Best Move using Minimax ---
        if let bestMove = findBestMove(currentBoard: board, depth: MAX_DEPTH) {
            print("AI Hard (Minimax): Chose move \(bestMove)")
            placeAiPieceAndEndTurn(at: bestMove)
        } else {
            // Fallback if minimax fails (shouldn't happen if empty cells exist)
            print("AI Hard (Minimax): Minimax failed to find a move! Falling back to Standard AI.")
            performStandardAiMove()
        }
    }
    
    // --- NEW: Minimax Initiator ---
    func findBestMove(currentBoard: [[CellState]], depth: Int) -> Position? {
        var bestScore = Int.min
        var bestMove: Position? = nil
        var alpha = Int.min // Renamed to avoid conflict
        let beta = Int.max  // Renamed to avoid conflict

        // --- MODIFIED Move Generation: Prioritize adjacent cells ---
        let adjacentMoves = findAdjacentEmptyCells(on: currentBoard)
        let candidateMoves: [Position]

        if !adjacentMoves.isEmpty {
            candidateMoves = adjacentMoves
            print("AI considering \(candidateMoves.count) adjacent moves initially.")
        } else {
            // Fallback if NO adjacent moves exist (very rare early game)
            candidateMoves = findEmptyCells(on: currentBoard)
            print("AI Warning: No adjacent moves found, considering all \(candidateMoves.count) empty cells.")
        }
        // --- End Move Generation ---

        guard !candidateMoves.isEmpty else { return nil }

        for move in candidateMoves {
            var tempBoard = currentBoard
            tempBoard[move.row][move.col] = state(for: aiPlayer)

            let score = minimax(board: tempBoard, depth: depth - 1, alpha: alpha, beta: beta, maximizingPlayer: false, currentPlayerToEvaluate: opponent(of: aiPlayer))

            print("Move \(move) evaluated with score: \(score)")

            if score > bestScore {
                bestScore = score
                bestMove = move
                alpha = max(alpha, bestScore) // Update alpha for the maximizing level
            }
            
            // Early exit if a winning move is found (alpha reaches WIN_SCORE)
            if alpha >= WIN_SCORE {
                 print("Found winning move sequence early during alpha update.")
                 return bestMove // Return the winning move
            }
            // No beta cutoff here at the top level

        } // End loop through candidate moves

        if bestMove == nil && !candidateMoves.isEmpty {
            print("Warning: Minimax completed but no best move found? Defaulting to first candidate.")
            bestMove = candidateMoves.first // Failsafe
        }

        print("Best move found: \(bestMove ?? Position(row: -1, col:-1)) with score: \(bestScore)")
        return bestMove
    }
    
    // --- NEW: Minimax with Alpha-Beta Pruning ---
    func minimax(board currentBoard: [[CellState]], depth: Int, alpha currentAlpha: Int, beta currentBeta: Int, maximizingPlayer: Bool, currentPlayerToEvaluate: Player) -> Int {

         var alpha = currentAlpha
         var beta = currentBeta

         // --- Base Cases ---
         let winner = checkForWinner(on: currentBoard)
         if winner == state(for: aiPlayer) { return WIN_SCORE }
         if winner == state(for: opponent(of: aiPlayer)) { return LOSE_SCORE }
         let emptyCells = findEmptyCells(on: currentBoard) // Still need all for draw check
         if emptyCells.isEmpty { return DRAW_SCORE }
         if depth == 0 { return evaluateBoard(board: currentBoard, playerMaximizing: aiPlayer) }
         // --- End Base Cases ---

         // --- MODIFIED Move Generation (Inside Minimax) ---
         let adjacentMoves = findAdjacentEmptyCells(on: currentBoard)
         let candidateMoves: [Position]

         if !adjacentMoves.isEmpty {
             candidateMoves = adjacentMoves
             // print("Depth \(depth): Considering \(candidateMoves.count) adjacent moves.") // DEBUG: Can be very verbose
         } else {
             // Fallback if no adjacent moves (e.g., opponent surrounded everything)
             candidateMoves = emptyCells // Use all empty if no adjacent
             // print("Depth \(depth): Warning: No adjacent moves found, considering all \(candidateMoves.count) empty.") // DEBUG
         }
         // --- End Move Generation ---


         if maximizingPlayer { // AI's turn (Maximize score)
             var maxEval = Int.min
             for move in candidateMoves {
                 var tempBoard = currentBoard
                 tempBoard[move.row][move.col] = state(for: currentPlayerToEvaluate)

                 let eval = minimax(board: tempBoard, depth: depth - 1, alpha: alpha, beta: beta, maximizingPlayer: false, currentPlayerToEvaluate: opponent(of: currentPlayerToEvaluate))

                 maxEval = max(maxEval, eval)
                 alpha = max(alpha, eval)
                 if beta <= alpha {
                     // print("Depth \(depth) (Max): Beta cutoff! (\(beta) <= \(alpha))") // DEBUG
                     break // Beta cut-off
                 }
             }
             return maxEval
         } else { // Opponent's turn (Minimize score)
             var minEval = Int.max
             for move in candidateMoves {
                 var tempBoard = currentBoard
                 tempBoard[move.row][move.col] = state(for: currentPlayerToEvaluate)

                 let eval = minimax(board: tempBoard, depth: depth - 1, alpha: alpha, beta: beta, maximizingPlayer: true, currentPlayerToEvaluate: opponent(of: currentPlayerToEvaluate))

                 minEval = min(minEval, eval)
                 beta = min(beta, eval)
                 if beta <= alpha {
                     // print("Depth \(depth) (Min): Alpha cutoff! (\(beta) <= \(alpha))") // DEBUG
                     break // Alpha cut-off
                 }
             }
             return minEval
         }
     }
    
    // --- NEW: Board Evaluation Heuristic ---
    func evaluateBoard(board: [[CellState]], playerMaximizing: Player) -> Int {
        // Check for terminal state first (should be caught by minimax base case, but safe)
        if checkForWinner(on: board) == state(for: playerMaximizing) { return WIN_SCORE }
        if checkForWinner(on: board) == state(for: opponent(of: playerMaximizing)) { return LOSE_SCORE }
        if findEmptyCells(on: board).isEmpty { return DRAW_SCORE }

        var totalScore = 0
        let lines = getAllLines(on: board) // Get all rows, cols, diagonals

        for line in lines {
            totalScore += evaluateLine(line: line, for: playerMaximizing)
            totalScore -= evaluateLine(line: line, for: opponent(of: playerMaximizing)) // Subtract opponent's score
        }

        return totalScore
    }

    // --- NEW: Helper to evaluate a single line ---
    func evaluateLine(line: [CellState], for player: Player) -> Int {
        let playerState = state(for: player)
        let opponentState = state(for: opponent(of: player))
        var score = 0
        let n = line.count

        // Iterate through windows of 5 and 6
        for i in 0...(n - 5) {
             let window5 = Array(line[i..<(i + 5)])
             var pCount = 0
             var eCount = 0
             for cell in window5 {
                  if cell == playerState { pCount += 1 }
                  else if cell == .empty { eCount += 1 }
             }

             // Check context for open/closed states
            let stateBefore: CellState? = (i > 0) ? line[i-1] : opponentState // Treat edge as opponent
            let stateAfter: CellState? = (i + 5 < n) ? line[i+5] : opponentState // Treat edge as opponent
            let isOpenBefore = stateBefore == .empty
            let isOpenAfter = stateAfter == .empty

            // --- Score based on patterns within window 5 ---
            if pCount == 5 { score += WIN_SCORE / 10 } // Strongly weight near-wins found mid-eval
            else if pCount == 4 && eCount == 1 {
                 // Potential closed four or part of open four
                 if isOpenBefore || isOpenAfter { score += SCORE_CLOSED_FOUR } // If at least one side is open, it's a closed four threat
            } else if pCount == 3 && eCount == 2 {
                 // Potential open or closed three
                 if isOpenBefore && isOpenAfter { score += SCORE_OPEN_THREE } // Open three
                 else if isOpenBefore || isOpenAfter { score += SCORE_CLOSED_THREE } // Closed three
            } else if pCount == 2 && eCount == 3 {
                // Potential open or closed two
                 if isOpenBefore && isOpenAfter { score += SCORE_OPEN_TWO }
                 else if isOpenBefore || isOpenAfter { score += SCORE_CLOSED_TWO }
            }

             // --- Check specifically for Open Four (window 6) ---
             if i <= (n - 6) {
                  let window6 = Array(line[i..<(i + 6)])
                  if window6[0] == .empty &&
                     window6[1] == playerState &&
                     window6[2] == playerState &&
                     window6[3] == playerState &&
                     window6[4] == playerState &&
                     window6[5] == .empty {
                       score += SCORE_OPEN_FOUR // Add score for open four
                  }
             }
        }
        return score
    }

    // --- NEW: Helper to get all relevant lines ---
    func getAllLines(on boardToCheck: [[CellState]]) -> [[CellState]] {
        var lines: [[CellState]] = []
        let n = boardSize
        // Rows
        for r in 0..<n { lines.append(getRow(r, on: boardToCheck)) }
        // Columns
        for c in 0..<n { lines.append(getColumn(c, on: boardToCheck)) }
        // Diagonals (only need those long enough potentially)
        lines.append(contentsOf: getDiagonals(on: boardToCheck).filter { $0.count >= 5 })
        return lines
    }
     enum ThreatType: Int { case five = 10000; case openFour = 5000; case closedFour = 450; case openThree = 400; case closedThree = 50 }
     func placeAiPieceAndEndTurn(at position: Position) { guard checkBounds(row: position.row, col: position.col) && board[position.row][position.col] == .empty else { print("!!! AI INTERNAL ERROR: placeAiPieceAndEndTurn called with invalid position \(position). Current: \(board[position.row][position.col])"); let recoveryMove = findEmptyCells(on: self.board).randomElement(); if let move = recoveryMove { print("!!! AI RECOVERY: Placing random piece at \(move) instead."); placePiece(atRow: move.row, col: move.col) } else { print("!!! AI RECOVERY FAILED: No empty cells left?"); view.isUserInteractionEnabled = true }; return }; placePiece(atRow: position.row, col: position.col) }
     func checkPotentialWin(player: Player, position: Position) -> Bool { var tempBoard = self.board; guard checkBounds(row: position.row, col: position.col) && tempBoard[position.row][position.col] == .empty else { return false }; tempBoard[position.row][position.col] = state(for: player); return checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[position.row][position.col], lastRow: position.row, lastCol: position.col) }
     func checkForWinOnBoard(boardToCheck: [[CellState]], playerState: CellState, lastRow: Int, lastCol: Int) -> Bool { guard playerState != .empty else { return false }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var count = 1; for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }; for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && boardToCheck[r][c] == playerState { count += 1 } else { break } }; if count >= 5 { return true } }; return false }
    func findEmptyCells(on boardToCheck: [[CellState]]) -> [Position] {
        var emptyPositions: [Position] = []
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if boardToCheck[r][c] == .empty {
                    emptyPositions.append(Position(row: r, col: c))
                }
            }
        }
        return emptyPositions
    }
    // Finds adjacent empty cells on a given board state
    func findAdjacentEmptyCells(on boardToCheck: [[CellState]]) -> [Position] {
        var adjacentEmpty = Set<Position>()
        let directions = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)]
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if boardToCheck[r][c] != .empty {
                    for (dr, dc) in directions {
                        let nr = r + dr
                        let nc = c + dc
                        if checkBounds(row: nr, col: nc) && boardToCheck[nr][nc] == .empty {
                            adjacentEmpty.insert(Position(row: nr, col: nc))
                        }
                    }
                }
            }
        }
        return Array(adjacentEmpty)
    }
    // Checks if *anyone* has won on the given board state
    func checkForWinner(on boardToCheck: [[CellState]]) -> CellState {
        // Check Rows & Columns
        for i in 0..<boardSize {
            if let winner = checkLineForWinner(getRow(i, on: boardToCheck)) { return winner }
            if let winner = checkLineForWinner(getColumn(i, on: boardToCheck)) { return winner }
        }
        // Check Diagonals
        for diag in getDiagonals(on: boardToCheck) {
             if let winner = checkLineForWinner(diag) { return winner }
        }
        return .empty // No winner
    }

    // Helper for checkForWinner: checks a single line array
    private func checkLineForWinner(_ line: [CellState]) -> CellState? {
        guard line.count >= 5 else { return nil }
        for i in 0...(line.count - 5) {
            let potentialWinner = line[i]
            if potentialWinner != .empty &&
               line[i+1] == potentialWinner &&
               line[i+2] == potentialWinner &&
               line[i+3] == potentialWinner &&
               line[i+4] == potentialWinner {
                return potentialWinner
            }
        }
        return nil
    }
     struct Position: Hashable, Equatable { var row: Int; var col: Int }
     func isBoardFull() -> Bool { return findEmptyCells(on: self.board).isEmpty }
     func checkBounds(row: Int, col: Int) -> Bool { return row >= 0 && row < boardSize && col >= 0 && col < boardSize }
     func state(for player: Player) -> CellState { return player == .black ? .black : .white }
     func opponent(of player: Player) -> Player { return player == .black ? .white : .black }

    // --- Winning Line Drawing ---
    func drawWinningLine(positions: [Position]) {
        guard positions.count >= 5, cellSize > 0 else {
             print("drawWinningLine: Not enough positions (\(positions.count)) or cellSize invalid.")
             return
        }
        winningLineLayer?.removeFromSuperlayer()

        // Draw the line itself
        let path = UIBezierPath()
        // ... (path calculation remains the same) ...
        let firstPos = positions.first!; let startX = boardPadding + CGFloat(firstPos.col) * cellSize; let startY = boardPadding + CGFloat(firstPos.row) * cellSize; path.move(to: CGPoint(x: startX, y: startY))
        let lastPos = positions.last!; let endX = boardPadding + CGFloat(lastPos.col) * cellSize; let endY = boardPadding + CGFloat(lastPos.row) * cellSize; path.addLine(to: CGPoint(x: endX, y: endY))

        let shapeLayer = CAShapeLayer()
        shapeLayer.path = path.cgPath
        shapeLayer.strokeColor = UIColor.red.withAlphaComponent(0.9).cgColor // Slightly less transparent
        shapeLayer.lineWidth = 6.0 // <-- Increased thickness
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.name = "winningLine"
        shapeLayer.shadowColor = UIColor.black.withAlphaComponent(0.5).cgColor // Add shadow to line
        shapeLayer.shadowOffset = CGSize(width: 0, height: 1)
        shapeLayer.shadowRadius = 2
        shapeLayer.shadowOpacity = 1.0

        // Animate the line drawing
        shapeLayer.strokeEnd = 0.0
        boardView.layer.addSublayer(shapeLayer)
        self.winningLineLayer = shapeLayer
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.duration = 0.4 // Slightly faster draw
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut) // Ease out feels better here
        shapeLayer.strokeEnd = 1.0
        shapeLayer.add(animation, forKey: "drawLineAnimation")

        print("Winning line drawn.")

        // --- MODIFIED: Highlight Winning Pieces ---
        let pulseDuration = 0.3
        let numberOfPulses = 3 // How many times to pulse

        // Small delay to let the line draw first
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration * 0.8) { [weak self] in // Start slightly before line finishes
            guard let self = self else { return }
            for position in positions {
                if self.checkBounds(row: position.row, col: position.col),
                   let pieceView = self.pieceViews[position.row][position.col] {

                    // Ensure animations start from identity
                    pieceView.layer.removeAllAnimations()
                    pieceView.transform = .identity
                    pieceView.alpha = 1.0

                    // Pulse animation
                    UIView.animate(withDuration: pulseDuration, delay: 0, options: [.allowUserInteraction, .curveEaseInOut], animations: {
                        // Animate multiple times within the block
                        UIView.modifyAnimations(withRepeatCount: CGFloat(numberOfPulses), autoreverses: true) {
                            pieceView.transform = CGAffineTransform(scaleX: 1.15, y: 1.15)
                            pieceView.alpha = 0.7
                        }
                    }) { _ in
                        // Completion block ensures it returns to normal *after* the pulses
                        // Add a slight delay to ensure the last reversal completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // Check if view still exists and reset definitely
                             if self.pieceViews[position.row][position.col] === pieceView {
                                pieceView.layer.removeAllAnimations() // Clean up just in case
                                pieceView.transform = .identity
                                pieceView.alpha = 1.0
                             }
                        }
                    }
                }
            }
        }
    }
    
    // --- Board State Getters ---
    func getRow(_ r: Int, on boardToCheck: [[CellState]]) -> [CellState] { /* ... */ guard r >= 0 && r < boardSize else { return [] }; return boardToCheck[r] }
    func getColumn(_ c: Int, on boardToCheck: [[CellState]]) -> [CellState] { /* ... */ guard c >= 0 && c < boardSize else { return [] }; return boardToCheck.map { $0[c] } }
    func getDiagonals(on boardToCheck: [[CellState]]) -> [[CellState]] { /* ... */ var diagonals: [[CellState]] = []; let n = boardSize; guard !boardToCheck.isEmpty && boardToCheck.count == n && boardToCheck[0].count == n else { return [] }; for c in 0..<n { var diag: [CellState] = []; var r_temp = 0; var c_temp = c; while checkBounds(row: r_temp, col: c_temp) { diag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp += 1 }; if diag.count >= 5 { diagonals.append(diag) } }; for r in 1..<n { var diag: [CellState] = []; var r_temp = r; var c_temp = 0; while checkBounds(row: r_temp, col: c_temp) { diag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp += 1 }; if diag.count >= 5 { diagonals.append(diag) } }; for c in 0..<n { var antiDiag: [CellState] = []; var r_temp = 0; var c_temp = c; while checkBounds(row: r_temp, col: c_temp) { antiDiag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp -= 1 }; if antiDiag.count >= 5 { diagonals.append(antiDiag) } }; for r in 1..<n { var antiDiag: [CellState] = []; var r_temp = r; var c_temp = n - 1; while checkBounds(row: r_temp, col: c_temp) { antiDiag.append(boardToCheck[r_temp][c_temp]); r_temp += 1; c_temp -= 1 }; if antiDiag.count >= 5 { diagonals.append(antiDiag) } }; return diagonals }

    // --- Reset Button Logic ---
    @IBAction func resetButtonTapped(_ sender: UIButton) {
        print("Reset button DOWN")
        animateButtonDown(sender)
        impactFeedbackGenerator.impactOccurred() // Haptic feedback
        sender.transform = .identity
        // Add release/cancel targets (needed because this is TouchDown)
        sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside)
        sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside)
        sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel)
        UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .curveEaseOut], animations: {
             sender.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
              if #unavailable(iOS 15.0) { sender.backgroundColor = UIColor(red: 0.88, green: 0.89, blue: 0.91, alpha: 1.0) }
              else { sender.alpha = 0.85 }
        }, completion: nil)

         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpInside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchUpOutside)
         sender.addTarget(self, action: #selector(resetButtonReleased(_:)), for: .touchCancel)
    }

    @IBAction func resetButtonReleased(_ sender: UIButton) {
        animateButtonUp(sender)
        UIView.animate(withDuration: 0.1, delay: 0, options: [.allowUserInteraction, .curveEaseIn], animations: {
            sender.transform = .identity
             if #unavailable(iOS 15.0) { sender.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0) }
             else { sender.alpha = 1.0 }
        }, completion: { _ in
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside)
            sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)
        })
        if currentGameState == .playing {
             print("Resetting game...")
             setupNewGame()
             if !isAiTurn { view.isUserInteractionEnabled = true }
             // If AI starts, startGame handles it.
        } else { print("Reset tapped while in setup state - doing nothing.") }
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside)
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside)
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)
    }

} // End of ViewController class

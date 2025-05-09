import UIKit
import AVFoundation // <-- Import AVFoundation for audio

class ViewController: UIViewController {
    struct Position: Hashable, Equatable { var row: Int; var col: Int }
    struct MoveRecord {
        let position: Position
        let player: Player // The player who made this move
    }
    private var moveHistory: [MoveRecord] = []

    // --- Outlets ---
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var boardView: UIView!
    @IBOutlet weak var resetButton: UIButton!
    private let undoButton = UIButton(type: .system)
    private let undoStatusLabel = UILabel()


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
    private var undoActionUsedThisGame: Bool = false
    let undoRuleInfoShownKey = "hasShownGomokuUndoRuleInfoBanner" // Renamed for clarity


    // --- Adaptive Setup UI Properties ---
    private var setupPortraitConstraints: [NSLayoutConstraint] = []
    private var setupLandscapeConstraints: [NSLayoutConstraint] = []
    private var currentSetupConstraints: [NSLayoutConstraint] = [] // Track active set

    // --- AI Control ---
    enum AIDifficulty { case easy, medium, hard } // Keep 'hard' enum value
    let aiPlayer: Player = .white
    private var selectedDifficulty: AIDifficulty = .easy
    var isAiTurn: Bool { currentGameMode == .humanVsAI && currentPlayer == aiPlayer }
    private var aiShouldCancelMove = false
    private var aiCalculationTurnID: Int = 0

    // --- NEW: Minimax AI Constants ---
    private let MAX_DEPTH = 3 // Initial search depth (Adjust for performance/strength)
    private let WIN_SCORE = 1000000
    private let LOSE_SCORE = -1000000
    private let DRAW_SCORE = 0
    // Significantly increase threat scores
    private let SCORE_OPEN_FOUR = 500000 // Was 50000
    private let SCORE_CLOSED_FOUR = 10000 // Was 4500 (Still forcing)
    private let SCORE_OPEN_THREE = 8000 // Was 4000 (Very important)
    // Keep lower threats less significant relative to the above
    private let SCORE_CLOSED_THREE = 300  // Was 500
    private let SCORE_OPEN_TWO = 50   // Was 100
    private let SCORE_CLOSED_TWO = 10   // Was 10
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
    private let moveCountLabel = UILabel()
    private var moveCount = 0
    private var infoBannerView: UIView?

    // --- Main Menu Button ---
    private let mainMenuButton = UIButton(type: .system)

    // --- Visual Polish Properties ---
    private var lastMovePosition: Position? = nil
    private var lastMoveIndicatorLayer: CALayer?
    private var shakeAnimation: CABasicAnimation? // To create shake only once
    private var turnIndicatorView: UIView?
    private var aiThinkingIndicatorView: UIView? // <-- NEW: AI Thinking Indicator View

    // --- Game Over Overlay UI Elements ---
    private let gameOverOverlayView = UIVisualEffectView()
    private let gameOverStatusLabel = UILabel()
    private let playAgainButton = UIButton(type: .system)
    private let overlayMainMenuButton = UIButton(type: .system)
    private var gameOverUIElements: [UIView] = []
    private let gameOverIconImageView = UIImageView() // <-- NEW: Icon for Game Over

    // --- Constraint Activation Flag ---
    private var constraintsActivated = false

    // --- Stored property for winning positions ---
    private var lastWinningPositions: [Position]? = nil

    // --- NEW: Audio & Haptic Properties ---
    private var audioPlayers: [String: AVAudioPlayer] = [:]
    private let lightImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light) // For general taps
    private let mediumImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium) // For human piece placement
    private let softImpactFeedbackGenerator = UIImpactFeedbackGenerator(style: .soft)   // For AI piece placement
    private let notificationFeedbackGenerator = UINotificationFeedbackGenerator() // For win/loss/error
    private let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light) // For general taps

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
        createUndoButtonAndStatusLabel()
        createUndoButtonAndStatusLabel()
        createMainMenuButton()
        createSetupUI()
        createNewGameOverUI()
        setupTurnIndicatorView()
        createAiThinkingIndicatorView()
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
        lightImpactFeedbackGenerator.prepare()
        mediumImpactFeedbackGenerator.prepare()
        softImpactFeedbackGenerator.prepare()
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
        let aspectRatioConstraint = boardView.heightAnchor.constraint(equalTo: boardView.widthAnchor, multiplier: 1.0); aspectRatioConstraint.priority = .required; let leadingConstraint = boardView.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 5)
        let trailingConstraint = boardView.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -5); let topConstraint = boardView.topAnchor.constraint(greaterThanOrEqualTo: safeArea.topAnchor, constant: 80)
        let bottomConstraint = boardView.bottomAnchor.constraint(lessThanOrEqualTo: safeArea.bottomAnchor, constant: -80); let widthConstraint = boardView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, constant: -40); widthConstraint.priority = .defaultHigh
        let heightConstraint = boardView.heightAnchor.constraint(equalTo: safeArea.heightAnchor, constant: -160); heightConstraint.priority = .defaultHigh
        NSLayoutConstraint.activate([centerXConstraint, centerYConstraint, aspectRatioConstraint, leadingConstraint, trailingConstraint, topConstraint, bottomConstraint, widthConstraint, heightConstraint])
        NSLayoutConstraint.activate([statusLabel.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 20), statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 20), statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -20), statusLabel.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor)])
        NSLayoutConstraint.activate([resetButton.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor, constant: -30), resetButton.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor), resetButton.leadingAnchor.constraint(greaterThanOrEqualTo: safeArea.leadingAnchor, constant: 30), resetButton.trailingAnchor.constraint(lessThanOrEqualTo: safeArea.trailingAnchor, constant: -30)])
        print("Game element constraints activated.")
    }
    // Update calls in createSetupUI:
    func createSetupUI() {
        print("Creating Setup UI")
        // gameTitleLabel
        gameTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        gameTitleLabel.text = "Gomoku"
        gameTitleLabel.font = UIFont.systemFont(ofSize: 52, weight: .heavy) // Slightly larger and heavier for impact
        gameTitleLabel.textColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0) // Dark gray, not pure black
        gameTitleLabel.textAlignment = .center
        gameTitleLabel.layer.shadowColor = UIColor.black.cgColor
        gameTitleLabel.layer.shadowOffset = CGSize(width: 0, height: 1.5) // NEW: Softer shadow offset
        gameTitleLabel.layer.shadowRadius = 3.0 // NEW: Softer shadow radius
        gameTitleLabel.layer.shadowOpacity = 0.15 // NEW: Softer shadow opacity
        gameTitleLabel.layer.masksToBounds = false
        view.addSubview(gameTitleLabel)

        // setupTitleLabel
        setupTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        setupTitleLabel.text = "Choose Game Mode"
        setupTitleLabel.font = UIFont.systemFont(ofSize: 24, weight: .medium) // NEW: Medium weight for less emphasis than main title
        setupTitleLabel.textColor = UIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.9) // Slightly lighter text
        setupTitleLabel.textAlignment = .center
        // No shadow for subtitle to keep it cleaner
        view.addSubview(setupTitleLabel)

        startEasyAIButton.translatesAutoresizingMaskIntoConstraints = false
        // configureSetupButton(startEasyAIButton, color: UIColor(red: 0.8, green: 0.95, blue: 0.85, alpha: 1.0)); // OLD
        // startEasyAIButton.setTitle("vs AI (Easy)", for: .normal); // OLD
        configureSetupButton(startEasyAIButton, title: "vs AI (Easy)", iconName: "brain.head.profile", color: UIColor(red: 0.82, green: 0.92, blue: 0.98, alpha: 1.0)) // Light Blueish
        startEasyAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside)
        view.addSubview(startEasyAIButton)

        startMediumAIButton.translatesAutoresizingMaskIntoConstraints = false
        // configureSetupButton(startMediumAIButton, color: UIColor(red: 0.95, green: 0.9, blue: 0.75, alpha: 1.0)); // OLD
        // startMediumAIButton.setTitle("vs AI (Medium)", for: .normal); // OLD
        configureSetupButton(startMediumAIButton, title: "vs AI (Medium)", iconName: "brain.head.profile", color: UIColor(red: 0.80, green: 0.88, blue: 0.95, alpha: 1.0)) // Slightly darker blueish
        startMediumAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside)
        view.addSubview(startMediumAIButton)

        startHardAIButton.translatesAutoresizingMaskIntoConstraints = false
        // configureSetupButton(startHardAIButton, color: UIColor(red: 0.95, green: 0.75, blue: 0.75, alpha: 1.0)); // OLD
        // startHardAIButton.setTitle("vs AI (Hard)", for: .normal); // OLD
        configureSetupButton(startHardAIButton, title: "vs AI (Hard)", iconName: "brain.head.profile", color: UIColor(red: 0.78, green: 0.85, blue: 0.92, alpha: 1.0)) // Even darker blueish
        startHardAIButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside)
        view.addSubview(startHardAIButton)

        startHvsHButton.translatesAutoresizingMaskIntoConstraints = false
        // configureSetupButton(startHvsHButton, color: UIColor(red: 0.85, green: 0.85, blue: 0.95, alpha: 1.0)); // OLD
        // startHvsHButton.setTitle("Human vs Human", for: .normal); // OLD
        configureSetupButton(startHvsHButton, title: "Human vs Human", iconName: "person.2.fill", color: UIColor(red: 0.88, green: 0.88, blue: 0.88, alpha: 1.0)) // Light Gray
        startHvsHButton.addTarget(self, action: #selector(didTapSetupButton(_:)), for: .touchUpInside)
        view.addSubview(startHvsHButton)

        setupUIElements = [gameTitleLabel, setupTitleLabel, startEasyAIButton, startMediumAIButton, startHardAIButton, startHvsHButton]
    }

    // Modify configureSetupButton
    func configureSetupButton(_ button: UIButton, title: String, iconName: String?, color: UIColor) { // Added title and iconName
        button.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        button.backgroundColor = color // Fallback for older iOS
        button.setTitleColor(.darkText, for: .normal) // Fallback
        button.layer.cornerRadius = 14 // Fallback

        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.title = title
            if let iconName = iconName, let icon = UIImage(systemName: iconName) {
                config.image = icon
                config.imagePadding = 10
                config.imagePlacement = .leading
            }
            config.baseBackgroundColor = color
            config.baseForegroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.9) // Slightly less harsh than pure darkText
            config.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 25, bottom: 15, trailing: 25) // Adjusted padding
            config.cornerStyle = .large
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: 20, weight: .semibold) // Slightly smaller font for setup buttons
                return outgoing
            }
            button.configuration = config
        } else {
            button.setTitle(title, for: .normal)
            // Manual icon adding for < iOS 15 would be more complex, let's assume iOS 15+ for icons via config.
            // If not, we might need to create a custom UIView for the button content.
            button.contentEdgeInsets = UIEdgeInsets(top: 15, left: 30, bottom: 15, right: 30)
        }

        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: 2) // Slightly larger shadow offset
        button.layer.shadowRadius = 4 // Slightly larger shadow radius
        button.layer.shadowOpacity = 0.12 // Slightly less opacity for a softer shadow
        button.layer.masksToBounds = false
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
    // --- NEW: AI Thinking Indicator Setup ---
    func createAiThinkingIndicatorView() {
        let indicatorSize: CGFloat = 16 // Size of the indicator circle
        let indicator = UIView()
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.backgroundColor = UIColor.systemBlue.withAlphaComponent(0.7) // Example color
        indicator.layer.cornerRadius = indicatorSize / 2
        indicator.isHidden = true // Start hidden
        indicator.alpha = 0.0 // Start invisible for fade-in
        view.addSubview(indicator)
        self.aiThinkingIndicatorView = indicator

        // Constraints (centered below status label)
        guard let statusLabel = statusLabel else { return }
        NSLayoutConstraint.activate([
            indicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8), // Below status label
            indicator.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor), // Centered horizontally with status label
            indicator.widthAnchor.constraint(equalToConstant: indicatorSize),
            indicator.heightAnchor.constraint(equalToConstant: indicatorSize)
        ])
        print("AI thinking indicator view created.")
    }
    func createMainMenuButton() { /* ... no changes needed here ... */
        print("Creating Main Menu Button");
        mainMenuButton.translatesAutoresizingMaskIntoConstraints = false;
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.plain();
            config.title = "‹ Menu";
            config.titleAlignment = .leading;
            config.baseForegroundColor = UIColor.systemGray;
            config.attributedTitle?.font = UIFont.systemFont(ofSize: 17, weight: .medium);
            config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 10) // Slightly more vertical padding
            mainMenuButton.configuration = config
        } else {
            mainMenuButton.setTitle("‹ Menu", for: .normal)
            mainMenuButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .medium) // Explicit font
            mainMenuButton.setTitleColor(UIColor.systemGray, for: .normal) // CHANGED
            mainMenuButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 10) // Slightly more vertical padding
        };
        mainMenuButton.backgroundColor = .clear;
        mainMenuButton.addTarget(self, action: #selector(didTapMenuButton), for: .touchUpInside); mainMenuButton.isHidden = true; view.addSubview(mainMenuButton) }
    func setupMainMenuButtonConstraints() { /* ... no changes needed here ... */ print("Setting up Main Menu Button constraints"); let safeArea = view.safeAreaLayoutGuide; NSLayoutConstraint.activate([ mainMenuButton.topAnchor.constraint(equalTo: safeArea.topAnchor, constant: 15), mainMenuButton.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor, constant: 20) ]) }
    // Modify createNewGameOverUI()
    func createNewGameOverUI() {
        print("Creating Game Over UI with Blur")
        gameOverOverlayView.translatesAutoresizingMaskIntoConstraints = false
        // gameOverOverlayView.effect = UIBlurEffect(style: .systemMaterialDark) // Will set this dynamically
        gameOverOverlayView.layer.cornerRadius = 20 // Slightly larger radius
        gameOverOverlayView.layer.masksToBounds = true
        gameOverOverlayView.isHidden = true

        // Icon Image View
        gameOverIconImageView.translatesAutoresizingMaskIntoConstraints = false
        gameOverIconImageView.contentMode = .scaleAspectFit
        gameOverIconImageView.alpha = 0.7 // Slightly transparent
        gameOverOverlayView.contentView.addSubview(gameOverIconImageView)

        gameOverOverlayView.contentView.addSubview(gameOverStatusLabel)
        gameOverOverlayView.contentView.addSubview(playAgainButton)
        gameOverOverlayView.contentView.addSubview(overlayMainMenuButton)
        view.addSubview(gameOverOverlayView)

        gameOverStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        gameOverStatusLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold) // Slightly smaller, icon will take space
        gameOverStatusLabel.textColor = .white // Default, might change
        gameOverStatusLabel.textAlignment = .center
        gameOverStatusLabel.numberOfLines = 0

        playAgainButton.translatesAutoresizingMaskIntoConstraints = false
        // configureGameOverButton(playAgainButton, title: "Play Again", color: UIColor.systemGreen.withAlphaComponent(0.8)) // OLD
        // Will configure dynamically
        playAgainButton.addTarget(self, action: #selector(didTapGameOverButton(_:)), for: .touchUpInside)

        overlayMainMenuButton.translatesAutoresizingMaskIntoConstraints = false
        // configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: UIColor.systemBlue.withAlphaComponent(0.8)) // OLD
        // Will configure dynamically
        overlayMainMenuButton.addTarget(self, action: #selector(didTapGameOverButton(_:)), for: .touchUpInside)

        gameOverUIElements = [gameOverOverlayView, gameOverIconImageView, gameOverStatusLabel, playAgainButton, overlayMainMenuButton]
    }
    // Modify configureGameOverButton to handle primary/secondary styling
    func configureGameOverButton(_ button: UIButton, title: String, color: UIColor, isPrimary: Bool) { // Added isPrimary
        button.setTitle(title, for: .normal)
        if #available(iOS 15.0, *) {
            var config = isPrimary ? UIButton.Configuration.filled() : UIButton.Configuration.tinted() // Use tinted for secondary
            config.baseBackgroundColor = isPrimary ? color : nil // Filled uses baseBackgroundColor
            config.baseForegroundColor = isPrimary ? .white : color // Tinted uses baseForegroundColor for text/icon
            config.cornerStyle = .capsule // More modern feel
            config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var outgoing = incoming
                outgoing.font = UIFont.systemFont(ofSize: isPrimary ? 19 : 17, weight: isPrimary ? .bold : .semibold)
                return outgoing
            }
            config.contentInsets = NSDirectionalEdgeInsets(top: isPrimary ? 12 : 10, leading: 25, bottom: isPrimary ? 12 : 10, trailing: 25)

            if !isPrimary { // Add a subtle border to secondary button
                config.background.strokeColor = color.withAlphaComponent(0.7)
                config.background.strokeWidth = 1.0
            }

            button.configuration = config
        } else {
            // Fallback for older iOS
            button.backgroundColor = isPrimary ? color : color.withAlphaComponent(0.15)
            button.setTitleColor(isPrimary ? .white : color, for: .normal)
            button.titleLabel?.font = UIFont.systemFont(ofSize: isPrimary ? 18 : 16, weight: .semibold)
            button.layer.cornerRadius = (button.frame.height / 2) > 0 ? (button.frame.height / 2) : 20 // Capsule like
            button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
            if !isPrimary {
                button.layer.borderColor = color.withAlphaComponent(0.7).cgColor
                button.layer.borderWidth = 1.0
            } else {
                button.layer.borderWidth = 0
            }
        }
        // Common shadow for both
        button.layer.shadowColor = UIColor.black.cgColor
        button.layer.shadowOffset = CGSize(width: 0, height: isPrimary ? 2 : 1)
        button.layer.shadowRadius = isPrimary ? 4 : 2
        button.layer.shadowOpacity = isPrimary ? 0.2 : 0.1
        button.layer.masksToBounds = false
    }
    // Modify setupGameOverUIConstraints() to include the icon
    func setupGameOverUIConstraints() {
        print("Setting up Game Over UI constraints")
        let safeArea = view.safeAreaLayoutGuide
        let buttonSpacing: CGFloat = 18 // Slightly less spacing
        let overlayContentView = gameOverOverlayView.contentView

        NSLayoutConstraint.activate([
            gameOverOverlayView.centerXAnchor.constraint(equalTo: safeArea.centerXAnchor),
            gameOverOverlayView.centerYAnchor.constraint(equalTo: safeArea.centerYAnchor),
            gameOverOverlayView.widthAnchor.constraint(equalTo: safeArea.widthAnchor, multiplier: 0.75), // Slightly wider
            gameOverOverlayView.heightAnchor.constraint(lessThanOrEqualTo: safeArea.heightAnchor, multiplier: 0.6), // Can be taller

            // Icon View Constraints
            gameOverIconImageView.topAnchor.constraint(equalTo: overlayContentView.topAnchor, constant: 25),
            gameOverIconImageView.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor),
            gameOverIconImageView.widthAnchor.constraint(equalToConstant: 60), // Size of the icon
            gameOverIconImageView.heightAnchor.constraint(equalToConstant: 60),

            // Status Label Constraints (below icon)
            gameOverStatusLabel.topAnchor.constraint(equalTo: gameOverIconImageView.bottomAnchor, constant: 15),
            gameOverStatusLabel.leadingAnchor.constraint(equalTo: overlayContentView.leadingAnchor, constant: 20),
            gameOverStatusLabel.trailingAnchor.constraint(equalTo: overlayContentView.trailingAnchor, constant: -20),

            // Buttons
            playAgainButton.topAnchor.constraint(equalTo: gameOverStatusLabel.bottomAnchor, constant: 25),
            playAgainButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor),
            // playAgainButton.widthAnchor.constraint(equalTo: overlayContentView.widthAnchor, multiplier: 0.7), // Make buttons wider

            overlayMainMenuButton.topAnchor.constraint(equalTo: playAgainButton.bottomAnchor, constant: buttonSpacing),
            overlayMainMenuButton.centerXAnchor.constraint(equalTo: overlayContentView.centerXAnchor),
            overlayMainMenuButton.widthAnchor.constraint(equalTo: playAgainButton.widthAnchor), // Match Play Again width
            overlayMainMenuButton.bottomAnchor.constraint(lessThanOrEqualTo: overlayContentView.bottomAnchor, constant: -25)
        ])
    }

    // --- Turn Indicator (Underline) ---
    func setupTurnIndicatorView() { /* ... no changes needed ... */ guard statusLabel != nil else { return }; let indicator = UIView(); indicator.translatesAutoresizingMaskIntoConstraints = false; indicator.backgroundColor = .clear; indicator.layer.cornerRadius = 1.5; indicator.isHidden = true; view.addSubview(indicator); self.turnIndicatorView = indicator; NSLayoutConstraint.activate([indicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 4), indicator.heightAnchor.constraint(equalToConstant: 3), indicator.centerXAnchor.constraint(equalTo: statusLabel.centerXAnchor)]); print("Turn indicator view created.") }
    func updateTurnIndicatorLine() { /* ... no changes needed ... */ guard let indicator = turnIndicatorView, let label = statusLabel else { return }; let targetColor: UIColor; let targetWidth: CGFloat; if gameOver || currentGameState != .playing { targetColor = .clear; targetWidth = 0 } else { targetColor = (currentPlayer == .black) ? UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.85) : UIColor.systemBlue.withAlphaComponent(0.75); targetWidth = label.intrinsicContentSize.width * 0.6 }; UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: { indicator.backgroundColor = targetColor; if let widthConstraint = indicator.constraints.first(where: { $0.firstAttribute == .width }) { widthConstraint.constant = targetWidth } else { indicator.widthAnchor.constraint(equalToConstant: targetWidth).isActive = true }; indicator.superview?.layoutIfNeeded() }, completion: nil); indicator.isHidden = (gameOver || currentGameState != .playing) }

    // --- Visibility Functions ---
    func showSetupUI() {
        print("Showing Setup UI")
        // Hide game elements instantly BEFORE transition
        statusLabel.isHidden = true
        boardView.isHidden = true
        resetButton.isHidden = true
        mainMenuButton.isHidden = true
        moveCountLabel.isHidden = true
        gameOverOverlayView.isHidden = true
        turnIndicatorView?.isHidden = true
        undoButton.isHidden = true
        undoStatusLabel.isHidden = true
        moveHistory.removeAll()
        updateUndoButtonState()
        hideAiThinkingIndicator() // <-- NEW: Hide AI indicator
        currentGameState = .setup
        setupMainBackground()

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
        currentGameState = .playing // Set state BEFORE setting up background
        setupMainBackground()      // <-- ADD: Refresh background for game

        
        let gameElementsToShow: [UIView?] = [statusLabel, boardView, resetButton, mainMenuButton, moveCountLabel, undoButton, undoStatusLabel] // <<< MODIFIED: Added undoButton

        // Transition TO Game UI
        UIView.transition(with: self.view, duration: 0.35, options: .transitionCrossDissolve, animations: {
            gameElementsToShow.forEach { $0?.isHidden = false } // Use optional chaining for outlets
            self.turnIndicatorView?.isHidden = false
            self.currentGameState = .playing // Set state during animation
            self.undoButton.isHidden = false
            self.updateUndoButtonState()
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
    
    private func setupUndoStatusLabel() {
        undoStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        undoStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular) // Smaller font
        undoStatusLabel.textColor = UIColor.darkGray.withAlphaComponent(0.8)
        undoStatusLabel.textAlignment = .left
        view.addSubview(undoStatusLabel) // Add to view hierarchy

        // Constraints for undoStatusLabel (e.g., to the left or right of undoButton)
        // Assuming undoButton is to the right of this label:
        guard let undoButton = self.undoButton as? UIButton, undoButton.superview != nil else { // Ensure undoButton exists and is in hierarchy
            print("Undo button not ready for status label constraints.")
            return
        }

        NSLayoutConstraint.activate([
            undoStatusLabel.centerYAnchor.constraint(equalTo: undoButton.centerYAnchor),
            // Place it to the left of the undo button
            undoStatusLabel.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -6), // Small spacing
        ])
        print("Undo Status Label created and constrained.")
    }
    
    // Helper enum for clarity
    enum GameOutcome { case win, loss, draw }

    // Modify showGameOverOverlay()
    func showGameOverOverlay(message: String) {
        print("Showing Game Over Overlay: \(message)")

        let outcome: GameOutcome // Define an enum or use string parsing
        if message.contains("Wins") {
            if message.contains("Black") && currentPlayer == .black || message.contains("White") && currentPlayer == .white {
                 // This logic is a bit complex for determining if HUMAN won.
                 // Let's simplify: if AI is NOT the winner, human (or first player in HvsH) won.
                if currentGameMode == .humanVsHuman {
                    outcome = .win // Assuming the current player who made the winning move is the "human winner"
                } else {
                    // Human vs AI: if AI is not the current player, human won.
                    outcome = (aiPlayer != currentPlayer) ? .win : .loss
                }
            } else {
                outcome = .loss // AI won, or other player in HvsH
            }
        } else {
            outcome = .draw
        }

        // --- Configure based on outcome ---
        let iconConfig = UIImage.SymbolConfiguration(pointSize: 50, weight: .medium)
        var blurEffectStyle: UIBlurEffect.Style = .systemMaterialDark
        var iconImageName: String = "flag.checkered.2.crossed" // Default
        var iconTintColor: UIColor = .white
        var statusTextColor: UIColor = .white
        var playAgainColor: UIColor = .systemGreen
        var menuColor: UIColor = .systemBlue

        switch outcome {
        case .win: // Human wins
            // blurEffectStyle = .systemMaterialLight // Lighter blur for win
            iconImageName = "trophy.fill"
            iconTintColor = UIColor(red: 0.95, green: 0.73, blue: 0.26, alpha: 1.0) // Gold
            statusTextColor = .white //UIColor(red: 0.1, green: 0.4, blue: 0.1, alpha: 1.0) // Dark Green on light blur
            playAgainColor = UIColor.systemGreen.withAlphaComponent(0.9)
            menuColor = UIColor.systemGray.withAlphaComponent(0.8)
            gameOverStatusLabel.text = "🏆 You Win!"
        case .loss: // Human loses (AI Wins)
            blurEffectStyle = .systemMaterialDark // Keep dark for loss
            iconImageName = "hand.thumbsdown.fill" // Or "figure.walk.motion" for AI walking away victoriously
            iconTintColor = UIColor(red: 0.8, green: 0.8, blue: 0.85, alpha: 1.0) // Light Gray
            statusTextColor = UIColor(white: 0.9, alpha: 0.9)
            playAgainColor = UIColor.systemBlue.withAlphaComponent(0.85) // More prominent "Play Again"
            menuColor = UIColor.systemGray2.withAlphaComponent(0.7)
            gameOverStatusLabel.text = "😕 AI Wins"
            if currentGameMode == .humanVsHuman {
                gameOverStatusLabel.text = "🏆 \(message)" // Keep original winner message for HvsH
                iconImageName = "trophy.fill" // Still a win for someone
                iconTintColor = UIColor(red: 0.95, green: 0.73, blue: 0.26, alpha: 1.0) // Gold
            }
        case .draw:
            blurEffectStyle = .systemMaterial // Neutral blur
            iconImageName = "scalemass.fill"
            iconTintColor = UIColor(white: 0.85, alpha: 1.0)
            statusTextColor = .white //UIColor(white: 0.2, alpha: 0.9) // Dark gray on neutral blur
            playAgainColor = UIColor.systemOrange.withAlphaComponent(0.85)
            menuColor = UIColor.systemGray.withAlphaComponent(0.8)
            gameOverStatusLabel.text = "🤝 Draw!"
        }

        gameOverOverlayView.effect = UIBlurEffect(style: blurEffectStyle)
        gameOverIconImageView.image = UIImage(systemName: iconImageName, withConfiguration: iconConfig)
        gameOverIconImageView.tintColor = iconTintColor
        gameOverStatusLabel.textColor = statusTextColor
        // The original message already has an icon, let's use the new label for the main text.
        // gameOverStatusLabel.text = displayMessage // Keep your original flair logic if preferred

        // Configure buttons
        configureGameOverButton(playAgainButton, title: "Play Again", color: playAgainColor, isPrimary: true)
        configureGameOverButton(overlayMainMenuButton, title: "Main Menu", color: menuColor, isPrimary: false)


        gameOverOverlayView.isHidden = false
        gameOverOverlayView.alpha = 0
        // Animate icon and text along with the overlay
        gameOverIconImageView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
        gameOverStatusLabel.transform = CGAffineTransform(translationX: 0, y: 10)
        gameOverOverlayView.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)

        view.bringSubviewToFront(gameOverOverlayView)
        resetButton.isHidden = true
        mainMenuButton.isHidden = true

        UIView.animate(withDuration: 0.45, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.2, options: .curveEaseOut, animations: {
            self.gameOverOverlayView.alpha = 1.0
            self.gameOverOverlayView.transform = .identity
            self.gameOverIconImageView.transform = .identity
            self.gameOverStatusLabel.transform = .identity
        }, completion: nil)

        view.isUserInteractionEnabled = true
        turnIndicatorView?.isHidden = true
        hideAiThinkingIndicator() // Ensure AI indicator is hidden
    }

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
        lightImpactFeedbackGenerator.impactOccurred()
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
    
    func createUndoButtonAndStatusLabel() {
        print("Creating Undo Button")
        undoButton.translatesAutoresizingMaskIntoConstraints = false
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled()
            config.image = UIImage(systemName: "arrow.uturn.backward.circle.fill")
            config.baseBackgroundColor = UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1.0) // A distinct shade
            config.baseForegroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
            undoButton.configuration = config
        } else {
            undoButton.setImage(UIImage(systemName: "arrow.uturn.backward.circle.fill"), for: .normal)
            undoButton.tintColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0)
            undoButton.backgroundColor = UIColor(red: 0.85, green: 0.88, blue: 0.92, alpha: 1.0)
            undoButton.layer.cornerRadius = 8
            undoButton.contentEdgeInsets = UIEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)
        }
        undoButton.accessibilityLabel = "Undo Last Move"
        undoButton.layer.shadowColor = UIColor.black.cgColor
        undoButton.layer.shadowOffset = CGSize(width: 0, height: 1)
        undoButton.layer.shadowRadius = 2.5
        undoButton.layer.shadowOpacity = 0.12
        undoButton.layer.masksToBounds = false

        undoButton.addTarget(self, action: #selector(undoButtonTapped(_:)), for: .touchUpInside)
        undoButton.addTarget(self, action: #selector(buttonTouchDown(_:)), for: .touchDown)
        undoButton.addTarget(self, action: #selector(buttonTouchDragExit(_:)), for: .touchDragExit)
        undoButton.addTarget(self, action: #selector(buttonTouchDragEnter(_:)), for: .touchDragEnter)
        undoButton.addTarget(self, action: #selector(buttonTouchCancel(_:)), for: .touchCancel)
        // Add a generic up handler to ensure animation completes
        undoButton.addTarget(self, action: #selector(buttonReleased(_:)), for: .touchUpInside)
        undoButton.addTarget(self, action: #selector(buttonReleased(_:)), for: .touchUpOutside)

        view.addSubview(undoButton)
        setupUndoButtonConstraints()
        
        // --- Setup Undo Status Label ---
        print("Creating Undo Status Label")
        undoStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        undoStatusLabel.font = UIFont.systemFont(ofSize: 12, weight: .regular)
        undoStatusLabel.textColor = UIColor.systemGray // Subtle color
        undoStatusLabel.textAlignment = .left // Or .right if you place it on the other side
        view.addSubview(undoStatusLabel)

        // Constraints for undoStatusLabel relative to undoButton
        NSLayoutConstraint.activate([
            undoStatusLabel.centerYAnchor.constraint(equalTo: undoButton.centerYAnchor, constant: 1), // Slight offset if needed for alignment
            undoStatusLabel.trailingAnchor.constraint(equalTo: undoButton.leadingAnchor, constant: -8), // Spacing
            // Optional: constraint to prevent it from being too wide if text is unexpectedly long
            // undoStatusLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 80)
        ])
        // --- End Setup Undo Status Label ---
        
        updateUndoButtonState() // Initial state update
    }
    
    
    // Add this generic handler if you don't have one for all buttons
    @objc private func buttonReleased(_ sender: UIButton) {
        animateButtonUp(sender)
    }


    // --- NEW: Undo Button Setup and Constraints ---
    // (Place this function before createUndoButton or ensure it's accessible)
    private func setupUndoButtonConstraints() {
        // Ensure constraints are only added once and resetButton is available
        guard !self.view.constraints.contains(where: { $0.firstItem === undoButton || $0.secondItem === undoButton }),
              let resetButton = resetButton else {
            if self.resetButton == nil {
                print("Error: Reset button is nil, cannot constrain Undo button relative to it yet.")
            }
            return
        }
        print("Setting up Undo Button constraints")
        NSLayoutConstraint.activate([
            undoButton.centerYAnchor.constraint(equalTo: resetButton.centerYAnchor),
            undoButton.trailingAnchor.constraint(equalTo: resetButton.leadingAnchor, constant: -15),
            // Let intrinsic content size determine width/height based on icon and padding
        ])
        print("Undo Button constraints activated.")
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
    
    func setupMainBackground() {
        backgroundGradientLayer?.removeFromSuperlayer()
        let gradient = CAGradientLayer()
        gradient.frame = self.view.bounds

        let topColor: CGColor
        let bottomColor: CGColor

        if currentGameState == .setup {
            // Subtle gradient for Setup Screen
            topColor = UIColor(red: 0.92, green: 0.93, blue: 0.94, alpha: 1.0).cgColor // Lighter, cooler top
            bottomColor = UIColor(red: 0.88, green: 0.89, blue: 0.90, alpha: 1.0).cgColor // Lighter, cooler bottom
        } else {
            // Existing gradient for Game Screen
            topColor = UIColor(red: 0.96, green: 0.97, blue: 0.98, alpha: 1.0).cgColor
            bottomColor = UIColor(red: 0.91, green: 0.92, blue: 0.93, alpha: 1.0).cgColor
        }

        gradient.colors = [topColor, bottomColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.view.layer.insertSublayer(gradient, at: 0)
        self.backgroundGradientLayer = gradient
    }
    func styleResetButton() { /* ... */
        guard let button = resetButton else { return }; print("Styling Reset Button (V3 - with Icon)...");
        if #available(iOS 15.0, *) {
            var config = UIButton.Configuration.filled();
            config.title = "Reset Game";
            config.attributedTitle?.font = UIFont.systemFont(ofSize: 16, weight: .semibold);
            config.image = UIImage(systemName: "arrow.counterclockwise.circle");
            config.imagePadding = 8; config.imagePlacement = .leading;
            config.baseBackgroundColor = UIColor(red: 0.90, green: 0.91, blue: 0.93, alpha: 1.0);
            config.baseForegroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1.0);
            config.cornerStyle = .medium;
            config.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 18, bottom: 10, trailing: 18);
            button.configuration = config;
            button.layer.shadowColor = UIColor.black.cgColor;
            button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false
        } else {
            let buttonBackgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0); let buttonTextColor = UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1.0); let buttonBorderColor = UIColor(red: 0.75, green: 0.75, blue: 0.75, alpha: 0.8); button.backgroundColor = buttonBackgroundColor; button.setTitleColor(buttonTextColor, for: .normal); button.setTitleColor(buttonTextColor.withAlphaComponent(0.5), for: .highlighted); button.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold); button.layer.cornerRadius = 8; button.layer.borderWidth = 0.75; button.layer.borderColor = buttonBorderColor.cgColor; button.layer.shadowColor = UIColor.black.cgColor; button.layer.shadowOffset = CGSize(width: 0, height: 1); button.layer.shadowRadius = 2.5; button.layer.shadowOpacity = 0.12; button.layer.masksToBounds = false; button.contentEdgeInsets = UIEdgeInsets(top: 10, left: 20, bottom: 10, right: 20)
        };
        print("Reset Button styling applied (V3).") }
    func styleStatusLabel() { /* ... */ guard let label = statusLabel else { return }; label.font = UIFont.systemFont(ofSize: 22, weight: .medium); label.textColor = UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0); label.textAlignment = .center; label.layer.shadowColor = UIColor.black.cgColor; label.layer.shadowOffset = CGSize(width: 0, height: 1); label.layer.shadowRadius = 2.0; label.layer.shadowOpacity = 0.1; label.layer.masksToBounds = false }

    // --- Drawing Functions ---
    func drawProceduralWoodBackground() {
        /* ... */
        woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll()
        guard boardView.bounds.width > 0 && boardView.bounds.height > 0 else { print("Skipping wood background draw: boardView bounds not ready."); return }
        print("Drawing procedural wood background into bounds: \(boardView.bounds)")
        let baseLayer = CALayer()
        baseLayer.frame = boardView.bounds
        baseLayer.backgroundColor = UIColor(red: 0.60, green: 0.45, blue: 0.30, alpha: 1.0).cgColor
        baseLayer.cornerRadius = boardView.layer.cornerRadius // Use boardView's radius
        baseLayer.masksToBounds = true // <-- IMPORTANT: Clip the wood layer
        boardView.layer.insertSublayer(baseLayer, at: 0)
        woodBackgroundLayers.append(baseLayer)
        let grainLayerCount = 35; let boardWidth = boardView.bounds.width; let boardHeight = boardView.bounds.height; for _ in 0..<grainLayerCount { let grainLayer = CALayer(); let randomDarkness = CGFloat.random(in: -0.08...0.12); let baseRed: CGFloat = 0.60; let baseGreen: CGFloat = 0.45; let baseBlue: CGFloat = 0.30;
            let grainColor = UIColor(
                red: max(0.15, min(0.85, baseRed + randomDarkness)),
                green: max(0.10, min(0.80, baseGreen + randomDarkness)),
                blue: max(0.05, min(0.75, baseBlue + randomDarkness)),
                alpha: CGFloat.random(in: 0.15...0.40)
            )
            grainLayer.backgroundColor = grainColor.cgColor
            let grainWidth = CGFloat.random(in: 1.5...4.0); let grainX = CGFloat.random(in: 0...(boardWidth - grainWidth)); grainLayer.frame = CGRect(x: grainX, y: 0, width: grainWidth, height: boardHeight); baseLayer.addSublayer(grainLayer) }; let lightingGradient = CAGradientLayer(); lightingGradient.frame = boardView.bounds; lightingGradient.cornerRadius = baseLayer.cornerRadius; lightingGradient.type = .radial; lightingGradient.colors = [UIColor(white: 1.0, alpha: 0.15).cgColor, UIColor(white: 1.0, alpha: 0.0).cgColor, UIColor(white: 0.0, alpha: 0.15).cgColor]; lightingGradient.locations = [0.0, 0.6, 1.0]; lightingGradient.startPoint = CGPoint(x: 0.5, y: 0.5); lightingGradient.endPoint = CGPoint(x: 1.0, y: 1.0); baseLayer.addSublayer(lightingGradient); baseLayer.borderWidth = 1.5; baseLayer.borderColor = UIColor(red: 0.2, green: 0.15, blue: 0.1, alpha: 0.85).cgColor }
    func drawBoard() { /* ... */ boardView.layer.sublayers?.filter { $0.name == "gridLine" }.forEach { $0.removeFromSuperlayer() }; guard cellSize > 0 else { print("Skipping drawBoard: cellSize is 0"); return }; guard woodBackgroundLayers.first != nil else { print("Cannot draw board: Wood background layer not found."); return }; let boardDimension = cellSize * CGFloat(boardSize - 1); let gridLineColor = UIColor(red: 0.35, green: 0.3, blue: 0.25, alpha: 0.55).cgColor; let gridLineWidth: CGFloat = 0.6; for i in 0..<boardSize { let vLayer = CALayer(); let xPos = boardPadding + CGFloat(i) * cellSize; vLayer.frame = CGRect(x: xPos - (gridLineWidth / 2), y: boardPadding, width: gridLineWidth, height: boardDimension); vLayer.backgroundColor = gridLineColor; vLayer.name = "gridLine"; boardView.layer.addSublayer(vLayer); let hLayer = CALayer(); let yPos = boardPadding + CGFloat(i) * cellSize; hLayer.frame = CGRect(x: boardPadding, y: yPos - (gridLineWidth / 2), width: boardDimension, height: gridLineWidth); hLayer.backgroundColor = gridLineColor; hLayer.name = "gridLine"; boardView.layer.addSublayer(hLayer) }; print("Board drawn with cell size: \(cellSize)") }
    func redrawPieces() { /* ... */ guard cellSize > 0 else { print("Skipping redrawPieces: cellSize is 0"); return }; boardView.subviews.forEach { $0.removeFromSuperview() }; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); for r in 0..<boardSize { for c in 0..<boardSize { let cellState = board[r][c]; if cellState == .black || cellState == .white { drawPiece(atRow: r, col: c, player: (cellState == .black) ? .black : .white, animate: false) }}} }
    
    func drawPiece(atRow row: Int, col: Int, player: Player, animate: Bool = true) {
        guard cellSize > 0 else { return };
        let pieceSize = cellSize * 0.88;
        let x = boardPadding + CGFloat(col) * cellSize - (pieceSize / 2);
        let y = boardPadding + CGFloat(row) * cellSize - (pieceSize / 2);
        let pieceFrame = CGRect(x: x, y: y, width: pieceSize, height: pieceSize);
        let pieceView = UIView(frame: pieceFrame); pieceView.backgroundColor = .clear;
        let gradientLayer = CAGradientLayer(); gradientLayer.frame = pieceView.bounds;
        gradientLayer.cornerRadius = pieceSize / 2;
        let c1, c2, c3, c4: UIColor // For a 4-stop gradient
        if player == .black {
            c1 = UIColor(white: 0.60, alpha: 1.0) // Highlight (slightly brighter)
            c2 = UIColor(white: 0.35, alpha: 1.0) // Main body
            c3 = UIColor(white: 0.15, alpha: 1.0) // Darker edge
            c4 = UIColor(white: 0.05, alpha: 1.0) // Deepest shadow/edge
        } else {
            c1 = UIColor(white: 1.0, alpha: 1.0)  // Brightest highlight
            c2 = UIColor(white: 0.92, alpha: 1.0) // Main body (slightly less bright than pure white)
            c3 = UIColor(white: 0.80, alpha: 1.0) // Softer shadow
            c4 = UIColor(white: 0.70, alpha: 1.0) // Edge tone
        }
        gradientLayer.colors = [c1.cgColor, c2.cgColor, c3.cgColor, c4.cgColor];
        gradientLayer.locations = [0.0, 0.1, 0.7, 1.0] // NEW: Adjusted locations for smoother falloff
        gradientLayer.startPoint = CGPoint(x: 0.3, y: 0.3) // NEW: More focused highlight
        gradientLayer.endPoint = CGPoint(x: 0.7, y: 0.7)   // NEW
        
        pieceView.layer.addSublayer(gradientLayer);
        pieceView.layer.cornerRadius = pieceSize / 2;
        pieceView.layer.borderWidth = 0.35; // NEW: Thinner border
        pieceView.layer.borderColor = (player == .black) ?
            UIColor(white: 0.1, alpha: 0.6).cgColor : // Darker, subtle border for black
            UIColor(white: 0.65, alpha: 0.5).cgColor; // Lighter, subtle border for white
        pieceView.layer.shadowColor = UIColor.black.cgColor;
        pieceView.layer.shadowOpacity = 0.30; // NEW: Softer opacity
        pieceView.layer.shadowOffset = CGSize(width: 0.75, height: 1.25); // NEW: Slightly less offset
        pieceView.layer.shadowRadius = 2.5; // NEW: More diffuse radius
        pieceView.layer.masksToBounds = false;
        pieceViews[row][col]?.removeFromSuperview();
        boardView.addSubview(pieceView);
        pieceViews[row][col] = pieceView;
        if animate {
            pieceView.alpha = 0.0;
            pieceView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5);
             UIView.animate(withDuration: 0.45, // Slightly longer for more noticeable spring
                            delay: 0,
                            usingSpringWithDamping: 0.55, // Lower damping = more bounciness
                            initialSpringVelocity: 0.8,  // Higher initial velocity
                            options: .curveEaseOut,
                            animations: {
                 pieceView.alpha = 1.0;
                 pieceView.transform = .identity;
             }, completion: nil)
        } else { pieceView.alpha = 1.0; pieceView.transform = .identity } }
    
    func showLastMoveIndicator(at position: Position) { /* ... */
        lastMoveIndicatorLayer?.removeFromSuperlayer();
        lastMoveIndicatorLayer = nil;
        guard cellSize > 0, !gameOver else { return };
        let indicatorSize = cellSize * 0.92;
        let x = boardPadding + CGFloat(position.col) * cellSize - (indicatorSize / 2);
        let y = boardPadding + CGFloat(position.row) * cellSize - (indicatorSize / 2);
        let indicatorFrame = CGRect(x: x, y: y, width: indicatorSize, height: indicatorSize);
        let indicator = CALayer();
        indicator.frame = indicatorFrame;
        indicator.cornerRadius = indicatorSize / 2;
        indicator.borderWidth = 2.2;
        indicator.borderColor = UIColor(hue: 0.15, saturation: 0.9, brightness: 0.95, alpha: 0.85).cgColor; // NEW: More saturated yellow
        
        indicator.opacity = 0.0;
        indicator.transform = CATransform3DMakeScale(0.8, 0.8, 1.0)
        let groupAnimation = CAAnimationGroup()
        groupAnimation.duration = 0.6 // Total duration for fade and one pulse cycle
        
        indicator.name = "lastMoveIndicator";
        boardView.layer.addSublayer(indicator);
        self.lastMoveIndicatorLayer = indicator;
        
        UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut, animations: {
            indicator.opacity = 0.85
            indicator.transform = CATransform3DIdentity // Animate to normal size
        }, completion: nil)
        
        let fadeIn = CABasicAnimation(keyPath: "opacity");
        fadeIn.fromValue = 0.0;
        fadeIn.toValue = 0.85;
        fadeIn.duration = 0.3;
        fadeIn.timingFunction = CAMediaTimingFunction(name: .easeIn)
        // Subtle scale pulse (optional, can be removed if too distracting)
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.0
        pulse.toValue = 1.05
        pulse.autoreverses = true
        pulse.duration = 0.3 // Half of groupAnimation.duration for one pulse up and down
        pulse.beginTime = 0.0 // Start immediately with fade-in
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)

        groupAnimation.animations = [fadeIn, pulse]
        groupAnimation.fillMode = .forwards // Keep final state
        groupAnimation.isRemovedOnCompletion = false // Keep final state

        indicator.add(groupAnimation, forKey: "lastMoveIndicatorAnimation")
        // Set final properties directly in case animation is interrupted or for state consistency
        indicator.opacity = 0.85
        indicator.transform = CATransform3DMakeScale(1.0, 1.0, 1.0) // Ensure scale is reset if only opacity is used later

        self.lastMoveIndicatorLayer = indicator
    }

    // --- Game Logic & Interaction ---
    func setupNewGameVariablesOnly() { /* ... */ currentPlayer = .black; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); gameOver = false; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); lastWinningPositions = nil }
    func setupNewGame() { /* ... ADDED RESETcellSize/Bounds */ print("setupNewGame called. Current Mode: \(currentGameMode)"); gameOver = false; currentPlayer = .black; statusLabel.text = "Black's Turn"; board = Array(repeating: Array(repeating: .empty, count: boardSize), count: boardSize); boardView.subviews.forEach { $0.removeFromSuperview() }; boardView.layer.sublayers?.filter { $0.name == "gridLine" || $0.name == "winningLine" || $0.name == "lastMoveIndicator"}.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.forEach { $0.removeFromSuperlayer() }; woodBackgroundLayers.removeAll(); winningLineLayer = nil; lastMoveIndicatorLayer = nil; lastMovePosition = nil; lastWinningPositions = nil; moveCount = 0; moveCountLabel.text = "Moves: 0"; pieceViews = Array(repeating: Array(repeating: nil, count: boardSize), count: boardSize); cellSize = 0; lastDrawnBoardBounds = .zero; aiShouldCancelMove = false; updateTurnIndicatorLine(); turnIndicatorView?.isHidden = false; undoActionUsedThisGame = false; updateUndoButtonState(); print("setupNewGame: Reset game state. Requesting layout update."); view.setNeedsLayout() }
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
        
        aiShouldCancelMove = false

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
        mediumImpactFeedbackGenerator.impactOccurred()
        // ----------------------------------------

        print("Human placing piece at (\(tappedRow), \(tappedCol))");
        // Now call placePiece, which will handle game logic and drawing
        placePiece(atRow: tappedRow, col: tappedCol)
    }
    
    func placePiece(atRow row: Int, col: Int) {
        guard currentGameState == .playing, !gameOver else { return }
        guard checkBounds(row: row, col: col) && board[row][col] == .empty else {
             print("Error: Attempted to place piece in invalid or occupied cell (\(row), \(col)). Current state: \(board[row][col])")
             if isAiTurn { print("!!! AI ERROR: AI attempted invalid move. Halting AI turn. !!!"); view.isUserInteractionEnabled = true; hideAiThinkingIndicator() } // <-- NEW: Hide indicator on AI error
             return
        }

        moveCount += 1
        moveCountLabel.text = "Moves: \(moveCount)"

        let piecePlayer = currentPlayer
        let moveRecord = MoveRecord(position: Position(row: row, col: col), player: piecePlayer)
        moveHistory.append(moveRecord)

        if isAiTurn && !gameOver { // isAiTurn reflects whose turn it *was* when AI decided the move
            playSound(key: "place") // AI also makes a sound
            softImpactFeedbackGenerator.impactOccurred() // Haptic for AI piece
        }
        let pieceState: CellState = state(for: piecePlayer)
        board[row][col] = pieceState
        drawPiece(atRow: row, col: col, player: piecePlayer, animate: true)

        let currentPosition = Position(row: row, col: col)
        self.lastMovePosition = currentPosition
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showLastMoveIndicator(at: currentPosition) }

        updateUndoButtonState()
        
        if let winningPositions = findWinningLine(playerState: pieceState, lastRow: row, lastCol: col) {
            gameOver = true; self.lastWinningPositions = winningPositions
            updateTurnIndicatorLine()
            let winnerName = (pieceState == .black) ? "Black" : "White"; let message = "\(winnerName) Wins!"
            statusLabel.text = message; print(message)

            if piecePlayer == aiPlayer {
                print("AI Wins. Playing lose sound.")
                playSound(key: "lose")
                notificationFeedbackGenerator.notificationOccurred(.error)
            } else {
                print("Human Wins. Playing win sound.")
                playSound(key: "win")
                notificationFeedbackGenerator.notificationOccurred(.success)
            }

            drawWinningLine(positions: winningPositions)
            showGameOverOverlay(message: message); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer()
            lastMoveIndicatorLayer = nil
            hideAiThinkingIndicator() // <-- NEW: Hide indicator on game over
            updateUndoButtonState()
        } else if isBoardFull() {
            gameOver = true; updateTurnIndicatorLine()
            statusLabel.text = "Draw!"; print("Draw!")

            playSound(key: "lose")
            notificationFeedbackGenerator.notificationOccurred(.warning)

            showGameOverOverlay(message: "Draw!"); view.isUserInteractionEnabled = true
            lastMoveIndicatorLayer?.removeFromSuperlayer()
            lastMoveIndicatorLayer = nil
            hideAiThinkingIndicator() // <-- NEW: Hide indicator on game over
            updateUndoButtonState()
        } else {
            switchPlayer() // Only switch if game not over
        }
    }

    func updateUndoButtonState() {
        let canUndoOverall: Bool
        // Explicitly check if we are in the .playing state and game is not over
        let isGameActiveAndUndoPossible = (currentGameState == .playing && !gameOver)

        if isGameActiveAndUndoPossible && !undoActionUsedThisGame {
            canUndoOverall = true
            undoStatusLabel.text = "(1 left)"
            undoStatusLabel.textColor = UIColor.systemGray // Normal color when available
            undoStatusLabel.isHidden = false
            undoButton.isHidden = false
        } else if isGameActiveAndUndoPossible && undoActionUsedThisGame {
            canUndoOverall = false // Cannot undo (used), but game is active
            undoStatusLabel.text = "(Used)"
            undoStatusLabel.textColor = UIColor.systemGray3 // More faded when used
            undoStatusLabel.isHidden = false
            undoButton.isHidden = false // Button still visible but will be disabled
        } else {
            // This block covers:
            // - currentGameState == .setup
            // - currentGameState == .playing && gameOver == true
            canUndoOverall = false
            undoStatusLabel.text = "" // Clear text
            undoStatusLabel.isHidden = true
            undoButton.isHidden = true
        }

        undoButton.isEnabled = canUndoOverall

        UIView.animate(withDuration: 0.2) {
            // Alpha for the button itself, only fully opaque if truly usable
            self.undoButton.alpha = (canUndoOverall && isGameActiveAndUndoPossible && !self.undoActionUsedThisGame) ? 1.0 : 0.4
        }
    }


    // Helper function to create and show the banner
    private func showUndoRuleInfoBanner() {
        // Prevent multiple banners
        guard self.infoBannerView == nil else { return }

        let bannerHeight: CGFloat = 50 // Adjust as needed
        let bannerWidth: CGFloat = view.bounds.width * 0.8
        let bannerX = (view.bounds.width - bannerWidth) / 2
        // Position it below the status label or top safe area
        let bannerY: CGFloat = view.safeAreaInsets.top + (statusLabel.frame.maxY - view.safeAreaInsets.top) + 20


        let banner = UIView(frame: CGRect(x: bannerX, y: -bannerHeight - 20, // Start off-screen (top)
                                         width: bannerWidth, height: bannerHeight))
        banner.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        banner.layer.cornerRadius = 10
        banner.clipsToBounds = true

        let label = UILabel(frame: banner.bounds.insetBy(dx: 10, dy: 5))
        label.text = "Undo used! (Once per game)"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        label.textAlignment = .center
        label.numberOfLines = 0
        banner.addSubview(label)

        view.addSubview(banner)
        self.infoBannerView = banner

        // Animate in
        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5, options: .curveEaseOut, animations: {
            banner.frame.origin.y = bannerY
        }) { _ in
            // Animate out after a delay
            UIView.animate(withDuration: 0.4, delay: 2.0, options: .curveEaseIn, animations: {
                banner.frame.origin.y = -bannerHeight - 20 // Animate off-screen (top)
                banner.alpha = 0.0
            }) { _ in
                banner.removeFromSuperview()
                if self.infoBannerView === banner { // Ensure it's the same banner
                     self.infoBannerView = nil
                }
            }
        }
        UserDefaults.standard.set(true, forKey: undoRuleInfoShownKey)
    }
    
    @objc func undoButtonTapped(_ sender: UIButton) {
        guard !gameOver, !undoActionUsedThisGame else {
            // print("Undo: Cannot undo. Game over or undo already used this game.")
            // If undoActionUsedThisGame is true, we might want to give a subtle feedback like a gentle shake
            if undoActionUsedThisGame && !gameOver {
                // Gentle shake for the undo button itself
                let animation = CABasicAnimation(keyPath: "position.x")
                animation.duration = 0.07
                animation.repeatCount = 2 // Shorter shake
                animation.autoreverses = true
                animation.fromValue = NSNumber(value: sender.center.x - 4)
                animation.toValue = NSNumber(value: sender.center.x + 4)
                sender.layer.add(animation, forKey: "position.x.shakeUndo")
                notificationFeedbackGenerator.notificationOccurred(.warning) // Haptic
            }
            return
        }

        // Show banner if it's the first time this session/ever
        if !UserDefaults.standard.bool(forKey: undoRuleInfoShownKey) {
            showUndoRuleInfoBanner()
        }

        // Proceed with AI cancellation or direct undo
        let performUndoClosure = { [weak self] in
            guard let self = self else { return }
            guard !self.gameOver, !self.undoActionUsedThisGame else { return }
            self.performOneShotUndo()
        }

        if self.currentGameMode == .humanVsAI && (self.aiThinkingIndicatorView?.isHidden == false) {
            print("Undo: AI is thinking. Cancelling AI calculation for undo.")
            self.aiShouldCancelMove = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { // Give AI a moment to acknowledge
                performUndoClosure()
            }
        } else {
            performUndoClosure()
        }
    }

    private func performOneShotUndo() {
        guard !gameOver, !undoActionUsedThisGame, !moveHistory.isEmpty else {
            print("Undo: Conditions not met for one-shot undo (game over, undo used, or no moves).")
            // If AI was cancelled, its thinking indicator should be hidden by its own cancellation logic.
            // Re-enable user interaction if it was disabled for AI thinking and AI is now cancelled.
            if currentGameMode == .humanVsAI && (aiThinkingIndicatorView?.isHidden ?? true) && !isAiTurn {
                 view.isUserInteractionEnabled = true
            }
            updateUndoButtonState()
            return
        }

        print("Undo: Performing one-shot undo.")
        playSound(key: "invalid") // Or a dedicated "undo" sound
        lightImpactFeedbackGenerator.impactOccurred()

        // Determine whose turn it was before the last move(s)
        // In HvH, undo one move. Player who made it gets the turn.
        // In HvAI:
        //   - If AI last moved, undo AI's move AND human's prior move. Turn goes to human.
        //   - If Human last moved (AI hasn't responded yet), undo human's move. Turn goes to human.

        let movesToPop: Int
        var nextPlayerAfterUndo: Player

        if currentGameMode == .humanVsHuman {
            guard let lastMoveRecord = moveHistory.last else { return }
            movesToPop = 1
            nextPlayerAfterUndo = lastMoveRecord.player // Player who made the move gets to play again
        } else { // Human vs AI
            guard let lastMoveRecord = moveHistory.last else { return }
            if lastMoveRecord.player == aiPlayer { // AI made the last move
                // Ensure there's a human move before AI's to undo
                guard moveHistory.count >= 2 else {
                    print("Undo Error (HvAI): AI moved, but no preceding human move in history.")
                    // This state should ideally not happen with a one-shot undo if AI always follows human.
                    // If it does, just undo AI's move and let human play.
                    movesToPop = 1
                    nextPlayerAfterUndo = opponent(of: aiPlayer) // Human's turn
                    return
                }
                movesToPop = 2 // Undo AI's move and human's prior move
            } else { // Human made the last move (before AI could respond)
                movesToPop = 1
            }
            nextPlayerAfterUndo = opponent(of: aiPlayer) // After undo in HvAI, it's always human's turn
        }

        guard moveHistory.count >= movesToPop else {
            print("Undo: Not enough moves in history for the operation (\(movesToPop) needed, \(moveHistory.count) available).")
            updateUndoButtonState()
            return
        }

        for _ in 0..<movesToPop {
            if let moveRecord = moveHistory.popLast() {
                let pos = moveRecord.position
                board[pos.row][pos.col] = .empty
                pieceViews[pos.row][pos.col]?.removeFromSuperview()
                pieceViews[pos.row][pos.col] = nil
                moveCount -= 1
            }
        }
        moveCountLabel.text = "Moves: \(moveCount)"

        currentPlayer = nextPlayerAfterUndo
        undoActionUsedThisGame = true // Mark undo as used for this game

        // Update last move indicator
        if let newLastMoveRecord = moveHistory.last {
            self.lastMovePosition = newLastMoveRecord.position
            showLastMoveIndicator(at: newLastMoveRecord.position)
        } else {
            self.lastMovePosition = nil
            lastMoveIndicatorLayer?.removeFromSuperlayer()
            lastMoveIndicatorLayer = nil
            if moveHistory.isEmpty { currentPlayer = .black } // Reset to black if board is empty
        }

        statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"
        updateTurnIndicatorLine()
        updateUndoButtonState() // This will now disable the button due to undoActionUsedThisGame = true

        // Ensure UI is interactive if it's now human's turn
        // (should generally be the case after undo, especially in HvAI)
        view.isUserInteractionEnabled = true
        hideAiThinkingIndicator() // Ensure it's hidden if AI was interrupted

        print("Undo: One-shot undo completed. Current player: \(currentPlayer). Undo used: \(undoActionUsedThisGame)")
    }
    func findWinningLine(playerState: CellState, lastRow: Int, lastCol: Int) -> [Position]? { /* ... */ guard playerState != .empty else { return nil }; let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]; for (dr, dc) in directions { var linePositions: [Position] = [Position(row: lastRow, col: lastCol)]; var count = 1; for i in 1..<5 { let r = lastRow + dr * i; let c = lastCol + dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }; for i in 1..<5 { let r = lastRow - dr * i; let c = lastCol - dc * i; if checkBounds(row: r, col: c) && board[r][c] == playerState { linePositions.append(Position(row: r, col: c)); count += 1 } else { break } }; if count >= 5 { linePositions.sort { ($0.row, $0.col) < ($1.row, $1.col) }; return Array(linePositions) } }; return nil }
    func switchPlayer() {
        guard !gameOver else { return }
        currentPlayer = (currentPlayer == .black) ? .white : .black
        statusLabel.text = "\(currentPlayer == .black ? "Black" : "White")'s Turn"
        updateTurnIndicatorLine()
        updateUndoButtonState()

        if isAiTurn {
            view.isUserInteractionEnabled = false
            statusLabel.text = "Computer (\(selectedDifficulty)) Turn..."
            print("Switching to AI (\(selectedDifficulty)) turn...")

            // --- NEW: Show AI Thinking Indicator ---
            showAiThinkingIndicator()
            // ---------------------------------------

            let delay = (selectedDifficulty == .hard) ? 0.6 : 0.4 // Keep existing delay
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self = self else { return }
                if !self.gameOver && self.isAiTurn {
                    self.performAiTurn()
                } else {
                    print("AI turn skipped (game over or state changed during delay)")
                    // --- NEW: Hide AI Thinking Indicator if turn skipped ---
                    self.hideAiThinkingIndicator()
                    // -----------------------------------------------------
                    if !self.gameOver { self.view.isUserInteractionEnabled = true }
                }
            }
        } else {
            print("Switching to Human turn...")
            view.isUserInteractionEnabled = true
            // --- NEW: Hide AI Thinking Indicator ---
            hideAiThinkingIndicator()
            // ---------------------------------------
        }
    }
    
    // --- NEW: AI Thinking Indicator Management ---
    func showAiThinkingIndicator() {
        guard let indicator = aiThinkingIndicatorView else { return }
        indicator.isHidden = false
        UIView.animate(withDuration: 0.2) {
            indicator.alpha = 1.0
        }

        // Add rotation animation
        let rotationAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotationAnimation.toValue = NSNumber(value: Double.pi * 2)
        rotationAnimation.duration = 1.5 // Duration of one rotation
        rotationAnimation.repeatCount = .infinity // Repeat indefinitely
        rotationAnimation.timingFunction = CAMediaTimingFunction(name: .linear) // Constant speed
        indicator.layer.add(rotationAnimation, forKey: "rotationAnimation")
         if selectedDifficulty == .hard && currentGameState == .playing { // Check game state too
             let pulseAnimation = CABasicAnimation(keyPath: "transform.scale")
             pulseAnimation.duration = 0.85
             pulseAnimation.fromValue = 1.0
             pulseAnimation.toValue = 1.25 // Slightly more noticeable pulse
             pulseAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
             pulseAnimation.autoreverses = true
             pulseAnimation.repeatCount = .infinity
             indicator.layer.add(pulseAnimation, forKey: "pulseAnimation")
         }
        print("AI thinking indicator shown and animating.")
    }

    func hideAiThinkingIndicator() {
        guard let indicator = aiThinkingIndicatorView else { return }
        UIView.animate(withDuration: 0.2, animations: {
            indicator.alpha = 0.0
        }) { _ in
            indicator.isHidden = true
            indicator.layer.removeAnimation(forKey: "rotationAnimation") // Stop animation
             indicator.layer.removeAnimation(forKey: "pulseAnimation") // Remove specific animation
             indicator.transform = .identity // Ensure scale is reset
            print("AI thinking indicator hidden and animation stopped.")
        }
    }

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
    // --- NEW Overload for Minimax ---
    // Finds empty cells on a GIVEN board where placing a piece *creates* the specified threat
    func findMovesCreatingThreat(on boardToCheck: [[CellState]], for player: Player, threat: ThreatType, emptyCells: [Position]) -> [Position] {
        var threatMoves: [Position] = []
        for position in emptyCells {
            var tempBoard = boardToCheck // Use the PASSED board state
            // Check if cell is empty on the passed board
            guard checkBounds(row: position.row, col: position.col) &&
                  tempBoard[position.row][position.col] == .empty else { continue }

            tempBoard[position.row][position.col] = state(for: player)

            if checkForThreatOnBoard(boardToCheck: tempBoard, player: player, threat: threat, lastMove: position) {
                 threatMoves.append(position)
            }
        }
        return threatMoves
    }

    // --- Keep Original Version for Medium/Easy AI ---
    // Finds empty cells on the CURRENT game board where placing a piece *creates* the specified threat
    func findMovesCreatingThreat(player: Player, threat: ThreatType, emptyCells: [Position]) -> [Position] {
        var threatMoves: [Position] = []
        for position in emptyCells {
            var tempBoard = self.board // Use self.board
            guard checkBounds(row: position.row, col: position.col) &&
                  tempBoard[position.row][position.col] == .empty else { continue }

            tempBoard[position.row][position.col] = state(for: player)

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
    
    // --- REVISED: Robust Open Three Check ---
    // Checks if placing 'player' at 'position' would *result* in an Open Three formation (_PPP_)
    func checkPotentialOpenThree(player: Player, position: Position, on boardToCheck: [[CellState]]) -> Bool {
        guard checkBounds(row: position.row, col: position.col) &&
              boardToCheck[position.row][position.col] == .empty else { return false } // Pre-condition

        var tempBoard = boardToCheck
        tempBoard[position.row][position.col] = state(for: player) // Simulate the move
        let playerState = state(for: player)
        let directions = [(0, 1), (1, 0), (1, 1), (1, -1)] // Horizontal, Vertical, Diag Down, Diag Up

        for (dr, dc) in directions {
            // We need to check all possible locations of the newly placed stone within a _PPP_ pattern.
            // Iterate through offsets such that 'position' could be any of the 'P's.
            for i in 1...3 { // Position could be the 1st, 2nd, or 3rd 'P'
                let startRow = position.row - dr * i
                let startCol = position.col - dc * i

                // Check bounds for the 5-cell window _PPP_
                guard checkBounds(row: startRow, col: startCol) &&
                      checkBounds(row: startRow + dr * 4, col: startCol + dc * 4) else { continue }

                // Check the specific _PPP_ pattern
                if tempBoard[startRow][startCol] == .empty &&                   // Slot 0: Empty
                   tempBoard[startRow + dr][startCol + dc] == playerState &&     // Slot 1: Player
                   tempBoard[startRow + dr * 2][startCol + dc * 2] == playerState && // Slot 2: Player
                   tempBoard[startRow + dr * 3][startCol + dc * 3] == playerState && // Slot 3: Player
                   tempBoard[startRow + dr * 4][startCol + dc * 4] == .empty {   // Slot 4: Empty
                    return true // Found an Open Three
                }
            }
        }
        return false // No Open Three created by this move
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
    func performAiTurn() {
        if aiShouldCancelMove {
            print("AI Turn (\(selectedDifficulty)): Cancelled before starting logic.")
            DispatchQueue.main.async { // Ensure UI updates are on main thread
                self.hideAiThinkingIndicator()
                if !self.gameOver { // Only re-enable if game is not over
                    // If it was AI's turn and it got cancelled, it should become human's turn
                    // or the undo action will set the correct player.
                    // For now, just ensure interaction is possible if game isn't over.
                    self.view.isUserInteractionEnabled = true
                }
                self.updateUndoButtonState()
                // Do NOT proceed with AI move placement
            }
            return // Important: exit the function
        }
        guard !gameOver else { view.isUserInteractionEnabled = true; return }; aiShouldCancelMove = false; aiCalculationTurnID += 1; print("AI Turn (\(selectedDifficulty)): Performing move..."); let startTime = CFAbsoluteTimeGetCurrent(); switch selectedDifficulty { case .easy: performSimpleAiMove(); DispatchQueue.main.async { self.checkAndReenableInteraction() }; case .medium: performStandardAiMove(); DispatchQueue.main.async { self.checkAndReenableInteraction() }; case .hard: performHardAiMove() }; let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime; print("AI (\(selectedDifficulty)) took \(String(format: "%.3f", timeElapsed)) seconds."); DispatchQueue.main.async { if !self.gameOver && !self.isAiTurn { self.view.isUserInteractionEnabled = true; self.statusLabel.text = "\(self.currentPlayer == .black ? "Black" : "White")'s Turn"; print("AI Turn (\(self.selectedDifficulty)): Completed. Re-enabled user interaction.") } else if self.gameOver { print("AI Turn (\(self.selectedDifficulty)): Game Over.") } else { print("AI Turn (\(self.selectedDifficulty)): Completed, still AI turn? (AI vs AI?)") } } }
    // Helper called after Easy/Medium AI (which run synchronously)
    func checkAndReenableInteraction() {
         if !self.gameOver && !self.isAiTurn { // If it's now human's turn
             self.view.isUserInteractionEnabled = true
             self.statusLabel.text = "\(self.currentPlayer == .black ? "Black" : "White")'s Turn"; // Update label correctly
             print("AI Turn (\(self.selectedDifficulty)): Completed. Re-enabled user interaction.")
         } else if self.gameOver {
             // Interaction enabled by showGameOverOverlay
             print("AI Turn (\(self.selectedDifficulty)): Game Over.")
         }
         // else: Still AI turn (AI vs AI) or some other state, leave interaction disabled.
    }
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
    // --- REVISED HARD AI LOGIC with Iterative Deepening & Time Limit ---
        func performHardAiMove() {
            let currentBoardState = self.board
            let emptyCellsOnBoard = findEmptyCells(on: currentBoardState) // Renamed for clarity
            guard !emptyCellsOnBoard.isEmpty else {
                print("AI Hard (Iterative): No empty cells left.")
                DispatchQueue.main.async { self.checkAndReenableInteraction() }
                return
            }

            let humanPlayer = opponent(of: aiPlayer)

            // Quick checks (immediate win/loss) - these are fast and should remain
            // For these quick checks, consider all empty cells to ensure safety/opportunism
            for cell in emptyCellsOnBoard {
                if checkPotentialWin(player: aiPlayer, position: cell, on: currentBoardState) {
                    print("AI Hard (Iterative): Found immediate winning move at \(cell)")
                    placeAiPieceAndEndTurn(at: cell); return
                }
            }
            var blockingMoves: [Position] = []
            for cell in emptyCellsOnBoard {
                if checkPotentialWin(player: humanPlayer, position: cell, on: currentBoardState) {
                    blockingMoves.append(cell)
                }
            }
            // If multiple blocking moves, the first one found is fine for this quick check.
            // The deeper search would evaluate them more thoroughly if no immediate block was taken.
            if let blockMove = blockingMoves.first {
                print("AI Hard (Iterative): Found immediate blocking move at \(blockMove)")
                placeAiPieceAndEndTurn(at: blockMove); return
            }

            let totalPieces = currentBoardState.flatMap({ $0 }).filter({ $0 != .empty }).count
            if totalPieces < 2 { // Opening moves
                let center = boardSize / 2
                let move = Position(row: center, col: center)
                if checkBounds(row: center, col: center) && currentBoardState[center][center] == .empty {
                    print("AI Hard (Iterative): First move, playing center.")
                    placeAiPieceAndEndTurn(at: move); return
                } else if let adjacentMove = findAdjacentEmptyCells(on: currentBoardState).randomElement() {
                    print("AI Hard (Iterative): First move, center taken, playing adjacent.")
                    placeAiPieceAndEndTurn(at: adjacentMove); return
                }
            }

            let calculationID = self.aiCalculationTurnID
            var bestMoveFromCompletedDepth: Position? = nil
            // Set a time limit slightly less than 3s to account for overhead.
            let timeBudget: TimeInterval = 2.7
            var searchDepthAchieved = 0

            print("AI Hard (Iterative): Starting iterative deepening up to depth \(MAX_DEPTH), time budget: \(timeBudget)s.")

            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                let overallStartTime = CFAbsoluteTimeGetCurrent()

                for currentIterativeDepth in 1...self.MAX_DEPTH {
                    let timeElapsedSoFar = CFAbsoluteTimeGetCurrent() - overallStartTime
                    let remainingTime = timeBudget - timeElapsedSoFar

                    if self.aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
                        print("AI Hard (Iterative): Calculation cancelled or turn ID mismatch before depth \(currentIterativeDepth).")
                        break
                    }
                    if remainingTime <= 0.1 { // Not enough time for a meaningful search (0.1s buffer)
                        print("AI Hard (Iterative): Time limit reached before starting depth \(currentIterativeDepth). Using best move from depth \(searchDepthAchieved).")
                        break
                    }

                    print("AI Hard (Iterative): Starting search for depth \(currentIterativeDepth) with \(String(format: "%.2f", remainingTime))s remaining...")
                    let iterationStartTimeForThisDepth = CFAbsoluteTimeGetCurrent()

                    let moveFoundAtThisDepth = self.findBestMove(
                        currentBoard: currentBoardState,
                        depth: currentIterativeDepth, // This is the depth for the current iteration
                        calculationID: calculationID,
                        timeLimitForThisIteration: remainingTime, // Pass remaining time budget
                        iterationStartTime: iterationStartTimeForThisDepth
                    )

                    let iterationTimeTaken = CFAbsoluteTimeGetCurrent() - iterationStartTimeForThisDepth

                    if self.aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
                        print("AI Hard (Iterative): Calculation cancelled or turn ID mismatch after depth \(currentIterativeDepth) search.")
                        break
                    }

                    if let move = moveFoundAtThisDepth {
                        bestMoveFromCompletedDepth = move // Store the move from this successfully completed depth
                        searchDepthAchieved = currentIterativeDepth
                        print("AI Hard (Iterative): Depth \(currentIterativeDepth) completed in \(String(format: "%.3f", iterationTimeTaken))s. Best move for this depth: \(move)")
                    } else {
                        print("AI Hard (Iterative): Depth \(currentIterativeDepth) search returned no move (likely timed out or cancelled within findBestMove). Will use previous depth's result if available.")
                        // If a shallower depth timed out, deeper depths will too.
                        break
                    }
                } // End iterative deepening loop

                let totalSearchTime = CFAbsoluteTimeGetCurrent() - overallStartTime
                print("AI Hard (Iterative): Total search time: \(String(format: "%.3f", totalSearchTime))s. Achieved depth: \(searchDepthAchieved).")

                DispatchQueue.main.async {
                    guard self.aiCalculationTurnID == calculationID, !self.aiShouldCancelMove else {
                        print("AI Hard (Iterative): Final result ignored, turn ID mismatch or cancelled.")
                        return
                    }
                    guard !self.gameOver && self.isAiTurn else {
                         print("AI Hard (Iterative): Game state changed during calculation. Aborting move placement.")
                         if !self.isAiTurn { self.view.isUserInteractionEnabled = true }
                         return
                     }

                    if let finalMoveToMake = bestMoveFromCompletedDepth {
                        print("AI Hard (Iterative): Applying best move \(finalMoveToMake) from deepest completed search (depth \(searchDepthAchieved)).")
                        self.placeAiPieceAndEndTurn(at: finalMoveToMake)
                    } else {
                        print("AI Hard (Iterative): Iterative deepening returned no move (even depth 1 failed or was cancelled immediately)! Falling back to a random adjacent or first empty cell.")
                        // Fallback: very basic move if IDS fails completely
                        let fallbackMove = self.findAdjacentEmptyCells(on: currentBoardState).randomElement() ?? emptyCellsOnBoard.first
                        if let move = fallbackMove {
                            self.placeAiPieceAndEndTurn(at: move)
                        } else {
                            print("AI Hard (Iterative): Catastrophic failure - no moves available for fallback.")
                            // UI should already be enabled or game over
                        }
                    }
                }
            }

            DispatchQueue.main.async {
                 print("AI Hard (Iterative): Re-enabling UI for Reset/Menu while thinking.")
                 self.view.isUserInteractionEnabled = true
            }
        }

    // --- REVISED: Minimax Initiator (findBestMove) with Time Limit Awareness ---
    func findBestMove(currentBoard: [[CellState]], depth: Int, calculationID: Int, timeLimitForThisIteration: TimeInterval, iterationStartTime: TimeInterval) -> Position? {
        if aiShouldCancelMove || self.aiCalculationTurnID != calculationID || timeLimitForThisIteration <= 0 {
            // print("findBestMove (depth \(depth)) cancelled or no time before start. Time left: \(timeLimitForThisIteration)") // DEBUG
            return nil
        }

        var bestScore = Int.min
        var bestMoves: [Position] = []
        var alpha = Int.min
        let beta = Int.max

        let adjacentMoves = findAdjacentEmptyCells(on: currentBoard)
        var candidateMoves: [Position] = !adjacentMoves.isEmpty ? adjacentMoves : findEmptyCells(on: currentBoard)
        guard !candidateMoves.isEmpty else { return nil }

        candidateMoves.sort { move1, move2 in
            staticallyEvaluateMove(move: move1, for: aiPlayer, on: currentBoard) >
            staticallyEvaluateMove(move: move2, for: aiPlayer, on: currentBoard)
        }

        for move in candidateMoves {
            if aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
                // print("findBestMove (depth \(depth)) cancelled during loop.") // DEBUG
                return bestMoves.first // Return best found so far if any
            }
            if CFAbsoluteTimeGetCurrent() - iterationStartTime >= timeLimitForThisIteration {
                // print("findBestMove (depth \(depth)): Time limit reached during move consideration. Returning current best.") // DEBUG
                return bestMoves.first // Return best found so far
            }

            var tempBoard = currentBoard
            tempBoard[move.row][move.col] = state(for: aiPlayer)

            // Calculate remaining time for the recursive minimax call
            let timeElapsedInFindBestMove = CFAbsoluteTimeGetCurrent() - iterationStartTime
            let remainingTimeForMinimax = timeLimitForThisIteration - timeElapsedInFindBestMove

            let score = minimax(board: tempBoard,
                                depth: depth - 1, // This is the *remaining* depth for the recursive call
                                alpha: alpha, beta: beta,
                                maximizingPlayer: false,
                                currentPlayerToEvaluate: opponent(of: aiPlayer),
                                calculationID: calculationID,
                                timeLimitForThisMinimaxCall: remainingTimeForMinimax, // Pass remaining time
                                iterationStartTime: iterationStartTime) // Keep original iteration start time for global check

            if aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
                 // print("findBestMove (depth \(depth)) cancelled after minimax return.") // DEBUG
                 return bestMoves.first
            }
            // Check if minimax returned a special "timeout/cancel" signal
            if score == Int.min + 1 || score == Int.max - 1 { // Minimax timed out or was cancelled
                // print("findBestMove (depth \(depth)): Minimax indicated timeout/cancellation. Stopping this depth.") // DEBUG
                return bestMoves.first // Return what we have, or nil if nothing yet for this depth
            }

            if score > bestScore {
                bestScore = score
                bestMoves = [move]
                alpha = max(alpha, bestScore)
            } else if score == bestScore {
                bestMoves.append(move)
            }

            if alpha >= WIN_SCORE {
                 return bestMoves.first
            }
        }

        if aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
             return bestMoves.first
        }
        // Check time one last time before complex tie-breaking
        if CFAbsoluteTimeGetCurrent() - iterationStartTime >= timeLimitForThisIteration && !bestMoves.isEmpty {
             // print("findBestMove (depth \(depth)): Time limit reached just before returning. Using current best from tied moves.") // DEBUG
             // Fall through to tie-breaking, but it might be cut short if tie-breaking is slow.
             // For simplicity, if time is up, just return the first of the bestMoves.
             return bestMoves.first
        }

        var finalMove: Position?
        if bestMoves.isEmpty {
            // This could happen if all moves timed out immediately or were cancelled.
            // Or if candidateMoves was empty initially (though guarded).
            // print("Warning: findBestMove (depth \(depth)) resulted in empty bestMoves. Candidates: \(candidateMoves.count)") // DEBUG
            finalMove = candidateMoves.first // A desperate fallback
        } else if bestMoves.count == 1 {
            finalMove = bestMoves.first
        } else {
            // Apply the enhanced tie-breaking from previous version
            finalMove = bestMoves.sorted { move1, move2 in
                let opponentPlayer = opponent(of: aiPlayer)
                let m1_blocksWin = checkPotentialWin(player: opponentPlayer, position: move1, on: currentBoard)
                let m2_blocksWin = checkPotentialWin(player: opponentPlayer, position: move2, on: currentBoard)
                if m1_blocksWin != m2_blocksWin { return m1_blocksWin }

                let m1_blocksO4 = checkPotentialThreat(player: opponentPlayer, threat: .openFour, position: move1, on: currentBoard)
                let m2_blocksO4 = checkPotentialThreat(player: opponentPlayer, threat: .openFour, position: move2, on: currentBoard)
                if m1_blocksO4 != m2_blocksO4 { return m1_blocksO4 }

                let m1_blocksO3 = checkPotentialThreat(player: opponentPlayer, threat: .openThree, position: move1, on: currentBoard)
                let m2_blocksO3 = checkPotentialThreat(player: opponentPlayer, threat: .openThree, position: move2, on: currentBoard)
                if m1_blocksO3 != m2_blocksO3 { return m1_blocksO3 }

                let score1_defensive = evaluateDefensiveTieBreak(move: move1, on: currentBoard, lastPlayerMove: nil)
                let score2_defensive = evaluateDefensiveTieBreak(move: move2, on: currentBoard, lastPlayerMove: nil)
                return score1_defensive > score2_defensive
            }.first
        }
        return finalMove
    }


    // `evaluateDefensiveTieBreak` remains the same as your V7/last version.
    // `staticallyEvaluateMove` also remains the same as your V7/last version (used for initial sort).

    // --- NEW: Helper for Defensive Tie-Breaking ---
    func evaluateDefensiveTieBreak(move: Position, on board: [[CellState]], lastPlayerMove: Position?) -> Int {
        var score = 0
        let center = boardSize / 2

        // 1. Proximity to center (higher score for closer)
        let distFromCenter = abs(move.row - center) + abs(move.col - center)
        score += (center * 2 - distFromCenter) * 10 // Max ~140. Multiplied to give it more weight than adjacency.

        // 2. Adjacency to ANY piece (encourages connected play)
        if isAdjacentToAnyPiece(position: move, on: board) {
            score += 50 // A decent bonus for being connected
        }

        // 3. Penalty for being too far from *all* existing pieces (discourage very isolated moves)
        var minDistanceToPiece = boardSize * 2 // Initialize with a large value
        var pieceFound = false
        for r in 0..<boardSize {
            for c in 0..<boardSize {
                if board[r][c] != .empty {
                    pieceFound = true
                    let dist = abs(move.row - r) + abs(move.col - c)
                    minDistanceToPiece = min(minDistanceToPiece, dist)
                }
            }
        }
        if pieceFound { // Only apply penalty if there are pieces on board
             // Higher distance = lower score (more penalty)
             // Max distance could be around boardSize.
             // Let's say penalty increases for distances > 2 or 3
            if minDistanceToPiece > 2 { // If the closest piece is more than 2 units away
                score -= (minDistanceToPiece - 2) * 20 // Penalty grows with distance
            }
        }


        // 4. Avoid immediately creating an opponent's open three (if this move allows it)
        //    Make a temporary board to check this.
        var tempBoard = board
        tempBoard[move.row][move.col] = state(for: aiPlayer) // Assume AI is making this move
        if findMovesCreatingThreat(on: tempBoard, for: opponent(of: aiPlayer), threat: .openThree, emptyCells: [move]).isEmpty {
            // Good: This move *doesn't* immediately allow opponent to make an open three *at this spot*.
            // This check is a bit simplistic as opponent can make O3 elsewhere.
            // A more robust check would be: after AI plays 'move', can opponent make O3 *anywhere*?
            // For now, let's check if placing AI's piece at 'move' then allows opponent to make O3 by playing *next* to it or completing one.
            // This is tricky to get right without a deeper look.
            // The `staticallyEvaluateMove` already has a penalty for this, so maybe this is redundant or needs to be more specific.
        } else {
            // This specific move, if AI takes it, allows opponent to form an Open Three by playing *at this very spot*
            // This shouldn't happen if the spot is empty, so this check might be flawed.
            // Let's re-think: if AI plays at 'move', does it enable an opponent's O3 *anywhere* on their next turn?
            // This is essentially what `evaluateBoard` does with `LOSE_SCORE + 10` or `-(SCORE_OPEN_THREE * 10)`.
            // So, the minimax score should already reflect this.
            // Perhaps we just rely on the center/adjacency for this defensive tie-break.
        }


        // print("Defensive Tie Break for \(move): \(score)") // DEBUG
        return score
    }
    
    // --- REVISED: Minimax with Alpha-Beta Pruning & Time Limit Awareness ---
    func minimax(board currentBoard: [[CellState]], depth: Int, alpha currentAlpha: Int, beta currentBeta: Int, maximizingPlayer: Bool, currentPlayerToEvaluate: Player, calculationID: Int, timeLimitForThisMinimaxCall: TimeInterval, iterationStartTime: TimeInterval) -> Int {
        // --- Cancellation & Overall Time Check (based on iterationStartTime) ---
        if aiShouldCancelMove || self.aiCalculationTurnID != calculationID {
            return maximizingPlayer ? (Int.min + 1) : (Int.max - 1) // Special signal for cancellation
        }
        // Check against the original start time of the *entire findBestMove iteration*
        if CFAbsoluteTimeGetCurrent() - iterationStartTime >= timeLimitForThisMinimaxCall { // Check against the overall budget for this findBestMove call
            // print("Minimax (depth \(depth)): Global time limit for iteration reached.") // DEBUG
            return maximizingPlayer ? (Int.min + 1) : (Int.max - 1) // Special signal for timeout
        }

        var alpha = currentAlpha
        var beta = currentBeta

        let winnerState = checkForWinner(on: currentBoard)
        if winnerState == state(for: aiPlayer) { return WIN_SCORE }
        if winnerState == state(for: opponent(of: aiPlayer)) { return LOSE_SCORE }

        let emptyCells = findEmptyCells(on: currentBoard)
        if emptyCells.isEmpty { return DRAW_SCORE }
        if depth == 0 { return evaluateBoard(board: currentBoard, playerMaximizing: aiPlayer) }

        let adjacentMoves = findAdjacentEmptyCells(on: currentBoard)
        var candidateMoves: [Position] = !adjacentMoves.isEmpty ? adjacentMoves : emptyCells
        guard !candidateMoves.isEmpty else { return DRAW_SCORE }

        candidateMoves.sort { move1, move2 in
            staticallyEvaluateMove(move: move1, for: currentPlayerToEvaluate, on: currentBoard) >
            staticallyEvaluateMove(move: move2, for: currentPlayerToEvaluate, on: currentBoard)
        }

        if maximizingPlayer {
            var maxEval = Int.min
            for move in candidateMoves {
                // Re-check time and cancellation before processing each move
                if aiShouldCancelMove || self.aiCalculationTurnID != calculationID || (CFAbsoluteTimeGetCurrent() - iterationStartTime >= timeLimitForThisMinimaxCall) {
                    return Int.min + 1 // Signal timeout/cancel
                }
                var tempBoard = currentBoard
                tempBoard[move.row][move.col] = state(for: currentPlayerToEvaluate)
                if checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[move.row][move.col], lastRow: move.row, lastCol: move.col) {
                    return WIN_SCORE // Immediate win found
                }

                let timeElapsedInMinimax = CFAbsoluteTimeGetCurrent() - iterationStartTime
                let remainingTimeForRecursiveCall = timeLimitForThisMinimaxCall - timeElapsedInMinimax

                let eval = minimax(board: tempBoard, depth: depth - 1, alpha: alpha, beta: beta, maximizingPlayer: false, currentPlayerToEvaluate: opponent(of: currentPlayerToEvaluate), calculationID: calculationID, timeLimitForThisMinimaxCall: remainingTimeForRecursiveCall, iterationStartTime: iterationStartTime)
                
                if eval == (Int.max - 1) { // Opponent's minimax call timed out/cancelled
                    return Int.min + 1 // Propagate timeout/cancel signal upwards
                }

                maxEval = max(maxEval, eval)
                alpha = max(alpha, eval)
                if beta <= alpha { break }
            }
            return maxEval
        } else { // Minimizing player
            var minEval = Int.max
            for move in candidateMoves {
                if aiShouldCancelMove || self.aiCalculationTurnID != calculationID || (CFAbsoluteTimeGetCurrent() - iterationStartTime >= timeLimitForThisMinimaxCall) {
                    return Int.max - 1 // Signal timeout/cancel
                }
                var tempBoard = currentBoard
                tempBoard[move.row][move.col] = state(for: currentPlayerToEvaluate)
                if checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[move.row][move.col], lastRow: move.row, lastCol: move.col) {
                    return LOSE_SCORE // Immediate loss found
                }

                let timeElapsedInMinimax = CFAbsoluteTimeGetCurrent() - iterationStartTime
                let remainingTimeForRecursiveCall = timeLimitForThisMinimaxCall - timeElapsedInMinimax

                let eval = minimax(board: tempBoard, depth: depth - 1, alpha: alpha, beta: beta, maximizingPlayer: true, currentPlayerToEvaluate: opponent(of: currentPlayerToEvaluate), calculationID: calculationID, timeLimitForThisMinimaxCall: remainingTimeForRecursiveCall, iterationStartTime: iterationStartTime)

                if eval == (Int.min + 1) { // AI's minimax call timed out/cancelled
                    return Int.max - 1 // Propagate timeout/cancel signal upwards
                }

                minEval = min(minEval, eval)
                beta = min(beta, eval)
                if beta <= alpha { break }
            }
            return minEval
        }
    }

    
    // --- REVISED: Board Evaluation Heuristic ---
    func evaluateBoard(board: [[CellState]], playerMaximizing: Player) -> Int {
        let playerMinimizing = opponent(of: playerMaximizing)
        let aiState = state(for: playerMaximizing)
        let humanState = state(for: playerMinimizing)

        // Check 1: Terminal State (Win/Loss/Draw)
        let winner = checkForWinner(on: board)
        if winner == aiState { return WIN_SCORE }
        if winner == humanState { return LOSE_SCORE }
        let emptyCells = findEmptyCells(on: board) // Keep for use
        if emptyCells.isEmpty { return DRAW_SCORE }

        // --- NEW: Check for EXISTING critical patterns on the board FIRST ---
        if hasExistingOpenFour(on: board, for: playerMinimizing) { // playerMinimizing is Human
            // print("DEBUG Eval: Human has EXISTING Open Four -> LOSE_SCORE + 5")
            return LOSE_SCORE + 5
        }
        if hasExistingOpenFour(on: board, for: playerMaximizing) { // playerMaximizing is AI
            // print("DEBUG Eval: AI has EXISTING Open Four -> WIN_SCORE - 5")
            return WIN_SCORE - 5 // Or a very high score like SCORE_OPEN_FOUR * 10
        }
        // Check for existing Open Threes if they are not immediately countered by AI's own O4/Win potential
        if hasExistingOpenThree(on: board, for: playerMinimizing) {
            // If AI cannot make an O4 or win on its next turn, this existing O3 for human is very bad.
            let aiCanMakeO4Next = !findMovesCreatingThreat(on: board, for: playerMaximizing, threat: .openFour, emptyCells: emptyCells).isEmpty
            let aiCanWinNext = !findMovesCreatingThreat(on: board, for: playerMaximizing, threat: .five, emptyCells: emptyCells).isEmpty
            if !aiCanMakeO4Next && !aiCanWinNext {
                // print("DEBUG Eval: Human has EXISTING Open Three, AI no immediate counter -> -(SCORE_OPEN_THREE * 15)")
                return -(SCORE_OPEN_THREE * 15) // Stronger penalty than just being able to make one
            }
        }
        if hasExistingOpenThree(on: board, for: playerMaximizing) {
            // If Human cannot make an O4 or win on their next turn, this existing O3 for AI is very good.
            let humanCanMakeO4Next = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .openFour, emptyCells: emptyCells).isEmpty
            let humanCanWinNext = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .five, emptyCells: emptyCells).isEmpty
            if !humanCanMakeO4Next && !humanCanWinNext {
                 // print("DEBUG Eval: AI has EXISTING Open Three, Human no immediate counter -> SCORE_OPEN_THREE * 2")
                // This bonus will be added to the general score later if not returned early
            }
        }


        // --- Check 2: IMMINENT OPPONENT THREATS (Moves that CREATE threats) ---
        let humanCanMakeOpenFour = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .openFour, emptyCells: emptyCells).isEmpty
        if humanCanMakeOpenFour {
            // print("DEBUG Eval: Human can MAKE Open Four -> LOSE_SCORE + 10")
            return LOSE_SCORE + 10
        }
        let humanCanMakeOpenThree = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .openThree, emptyCells: emptyCells).isEmpty
        if humanCanMakeOpenThree {
            // print("DEBUG Eval: Human can MAKE Open Three -> -(SCORE_OPEN_THREE * 10)")
            return -(SCORE_OPEN_THREE * 10)
        }

        // --- Check 3: IMMINENT AI THREATS (Moves that CREATE threats) ---
         let aiCanMakeOpenFour = !findMovesCreatingThreat(on: board, for: playerMaximizing, threat: .openFour, emptyCells: emptyCells).isEmpty
         if aiCanMakeOpenFour {
             // print("DEBUG Eval: AI can MAKE Open Four -> SCORE_OPEN_FOUR * 2")
             return SCORE_OPEN_FOUR * 2
         }
         let aiCanMakeOpenThree = !findMovesCreatingThreat(on: board, for: playerMaximizing, threat: .openThree, emptyCells: emptyCells).isEmpty
         // aiCanMakeOpenThree flag is used later if we don't return early

        // --- Check 4: General Line Evaluation ---
        var aiScoreFromPatterns = 0
        var humanScoreFromPatterns = 0
        let lines = getAllLines(on: board)

        for line in lines {
            // Pass board for context if needed by evaluateLineForPatternScores in future
            aiScoreFromPatterns += evaluateLineForPatternScores(line: line, for: playerMaximizing)
            humanScoreFromPatterns += evaluateLineForPatternScores(line: line, for: playerMinimizing)
        }

        var totalScore = aiScoreFromPatterns - humanScoreFromPatterns

        // Add bonus for AI's *existing* Open Three if not countered and not returned early
        if hasExistingOpenThree(on: board, for: playerMaximizing) {
            let humanCanMakeO4Next = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .openFour, emptyCells: emptyCells).isEmpty
            let humanCanWinNext = !findMovesCreatingThreat(on: board, for: playerMinimizing, threat: .five, emptyCells: emptyCells).isEmpty
            if !humanCanMakeO4Next && !humanCanWinNext {
                totalScore += SCORE_OPEN_THREE * 2 // Add bonus for existing, uncountered O3
            }
        }
        // Add bonus if AI *can make* an Open Three and we didn't return early for it
        else if aiCanMakeOpenThree {
            totalScore += SCORE_OPEN_THREE
        }

        return totalScore
    }

    // NEW Helper function to check for existing Open Four
    func hasExistingOpenFour(on boardToCheck: [[CellState]], for player: Player) -> Bool {
        let playerState = state(for: player)
        let lines = getAllLines(on: boardToCheck)
        for line in lines {
            if line.count < 6 { continue } // Need space for _ P P P P _
            for i in 0...(line.count - 6) {
                if line[i] == .empty &&
                   line[i+1] == playerState &&
                   line[i+2] == playerState &&
                   line[i+3] == playerState &&
                   line[i+4] == playerState &&
                   line[i+5] == .empty {
                    return true
                }
            }
        }
        return false
    }

    // NEW Helper function to check for existing Open Three
    func hasExistingOpenThree(on boardToCheck: [[CellState]], for player: Player) -> Bool {
        let playerState = state(for: player)
        let lines = getAllLines(on: boardToCheck)
        for line in lines {
            if line.count < 5 { continue } // Need space for _ P P P _
            for i in 0...(line.count - 5) {
                if line[i] == .empty &&
                   line[i+1] == playerState &&
                   line[i+2] == playerState &&
                   line[i+3] == playerState &&
                   line[i+4] == .empty {
                    return true
                }
            }
        }
        return false
    }

    // RENAMED from evaluateLineForMinorThreats
    // This function will now score Open Threes, Closed Fours, Closed Threes, and Twos directly from patterns.
    // Open Fours are handled by hasExistingOpenFour.
    func evaluateLineForPatternScores(line: [CellState], for player: Player) -> Int {
        let playerState = state(for: player)
        let opponentState = state(for: opponent(of: player))
        var score = 0
        let n = line.count

        // Note: hasExistingOpenThree and hasExistingOpenFour already cover these checks globally.
        // This function should focus on threats not already covered by the immediate high-priority checks in evaluateBoard.
        // Specifically, Closed Fours, Closed Threes, and Twos.
        // Open Threes are scored by hasExistingOpenThree and added to totalScore if applicable.

        // Check for Closed Four: XPPPP_ or _PPPPX or EPPPPX or XPPPPE (where X is opponent or edge)
        if n >= 5 {
            for i in 0...(n - 5) { // Window of 5: P P P P E or E P P P P
                let window5 = Array(line[i..<(i + 5)])
                var pCount = 0
                var eCount = 0
                for cell_idx in 0..<5 {
                    let cell = window5[cell_idx]
                    if cell == playerState { pCount += 1 }
                    else if cell == .empty { eCount += 1 }
                    else if cell == opponentState { pCount = -1; break } // Opponent blocks within the 5, invalidate
                }
                if pCount == -1 { continue }


                if pCount == 4 && eCount == 1 { // Potential PPPP_ or _PPPP
                    // Context for the 5-cell window: line[i-1] and line[i+5]
                    let beforeIsPlayer = (i > 0 && line[i-1] == playerState)
                    let afterIsPlayer = (i + 5 < n && line[i+5] == playerState)

                    // Avoid double counting parts of a 5-in-a-row (already handled by WIN_SCORE)
                    if beforeIsPlayer || afterIsPlayer { continue }


                    let beforeIsEmpty = (i == 0 || line[i-1] == .empty)
                    let beforeIsOpponent = (i > 0 && line[i-1] == opponentState)

                    let afterIsEmpty = (i + 5 == n || line[i+5] == .empty)
                    let afterIsOpponent = (i + 5 < n && line[i+5] == opponentState)

                    // A closed four requires one side to be blocked (opponent or edge) and the other side to be open (empty).
                    if (beforeIsEmpty && (afterIsOpponent || i + 5 == n)) ||
                       (afterIsEmpty && (beforeIsOpponent || i == 0)) {
                        score += SCORE_CLOSED_FOUR
                    }
                }
            }
        }

        // Check for Closed Three: XPPP_E or E_PPPX (where X is opponent or edge)
        if n >= 5 {
             for i in 0...(n - 5) { // Window of 5
                 let window5 = Array(line[i..<(i + 5)])
                 var pCount = 0
                 var eCount = 0
                 for cell_idx in 0..<5 {
                    let cell = window5[cell_idx]
                    if cell == playerState { pCount += 1 }
                    else if cell == .empty { eCount += 1 }
                    else if cell == opponentState { pCount = -1; break } // Opponent blocks within the 5
                 }
                 if pCount == -1 { continue }

                 if pCount == 3 && eCount == 2 { // Potential PPP_ _ or _ PPP _ or _ _ PPP
                     // This is an open three if context is E _PPP_ E, handled by hasExistingOpenThree.
                     // We are looking for X _PPP_ E or E _PPP_ X.
                     let beforeIsEmpty = (i == 0 || line[i-1] == .empty)
                     let beforeIsOpponent = (i > 0 && line[i-1] == opponentState)

                     let afterIsEmpty = (i + 5 == n || line[i+5] == .empty)
                     let afterIsOpponent = (i + 5 < n && line[i+5] == opponentState)

                     if (beforeIsEmpty && (afterIsOpponent || i + 5 == n)) ||
                        (afterIsEmpty && (beforeIsOpponent || i == 0)) {
                         // Check if it's NOT an open three (E _PPP_ E)
                         if !(beforeIsEmpty && afterIsEmpty) {
                            score += SCORE_CLOSED_THREE
                         }
                     }
                 }
             }
        }

        // Check for Twos (Open and Closed)
        // Pattern: E P P E _ (Open Two) or X P P E _ (Closed Two)
        if n >= 4 { // Need at least E P P E
            for i in 0...(n - 4) {
                let p1 = line[i+1]
                let p2 = line[i+2]

                if p1 == playerState && p2 == playerState {
                    // Have P P at i+1, i+2
                    let before = line[i]
                    let after = line[i+3]

                    if before == .empty && after == .empty {
                        // E P P E
                        // Check one more further out for _ E P P E _
                        let beforeBeforeIsEmpty = (i == 0 || line[i-1] == .empty)
                        let afterAfterIsEmpty = (i+4 == n || line[i+4] == .empty)
                        if beforeBeforeIsEmpty && afterAfterIsEmpty { // Prefer _E P P E_ for open two
                             score += SCORE_OPEN_TWO
                        } else { // E P P E counts as closed if not fully open
                             score += SCORE_CLOSED_TWO
                        }
                    } else if before == .empty || after == .empty {
                        // X P P E or E P P X
                        score += SCORE_CLOSED_TWO
                    }
                }
            }
        }
        return score
    }

    // --- REVISED V6: Helper for Static Move Evaluation (Move Ordering + Threat Mitigation) ---
    // Assigns a score for sorting moves, prioritizing critical actions.
    // Higher score = higher priority in the search.
    func staticallyEvaluateMove(move: Position, for player: Player, on boardToCheck: [[CellState]]) -> Int {
        let opponent = self.opponent(of: player)
        var score = 0
        let center = boardSize / 2 // e.g., 7 for boardSize 15

        // --- Priorities 1-10 (Revised) ---
        // Use large, distinct values to ensure clear prioritization.

        // 1. Immediate Win for 'player'? (MUST DO)
        if checkPotentialWin(player: player, position: move, on: boardToCheck) {
            return 100_000_000 // Highest priority
        }

        // 2. Immediate Block of opponent's win? (MUST DO)
        if checkPotentialWin(player: opponent, position: move, on: boardToCheck) {
            return 90_000_000 // Second highest
        }

        // 3. Create Open Four for 'player'?
        var createsOpenFour = false
        if checkPotentialThreat(player: player, threat: .openFour, position: move, on: boardToCheck) {
            score += 70_000_000
            createsOpenFour = true
        }

        // 4. Block opponent's Open Four?
        if checkPotentialThreat(player: opponent, threat: .openFour, position: move, on: boardToCheck) {
             score += createsOpenFour ? 5_000_000 : 80_000_000
        }

        // 5. Block opponent's Open Three? (Very important defense)
        var blocksOpenThree = false
        if checkPotentialThreat(player: opponent, threat: .openThree, position: move, on: boardToCheck) {
             score += 6_000_000 // High value for blocking O3
             blocksOpenThree = true
        }

        // 6. Create Open Three for 'player'?
        if checkPotentialThreat(player: player, threat: .openThree, position: move, on: boardToCheck) {
            score += blocksOpenThree ? 50_000 : 500_000 // Creating O3 << Blocking opponent's O3
        }

        // 7. Block opponent's Closed Four
         if checkPotentialThreat(player: opponent, threat: .closedFour, position: move, on: boardToCheck) {
             score += 40_000
         }
         // 8. Create own Closed Four
          if checkPotentialThreat(player: player, threat: .closedFour, position: move, on: boardToCheck) {
              score += 30_000
          }
        // 9. Block opponent's Closed Three
         if checkPotentialThreat(player: opponent, threat: .closedThree, position: move, on: boardToCheck) {
             score += 4_000
         }
        // 10. Create own Closed Three
         if checkPotentialThreat(player: player, threat: .closedThree, position: move, on: boardToCheck) {
              score += 3_000
          }
        // --- End Priorities 1-10 ---

        // --- NEW: Tie-Breaking Heuristics (Applied only if score is still low) ---
        if score < 1000 { // Only apply if no major tactical reason was found above
            // Bonus for proximity to center (prefer center control)
            let distFromCenter = abs(move.row - center) + abs(move.col - center)
            score += (center * 2 - distFromCenter) // Max bonus = 14, Min bonus = 0

            // --- NEW: Penalty for creating opponent's threats (if possible) ---
            // This is the key change.  If the move *creates* an open three for the opponent,
            // give it a *negative* score.  This is a *much* stronger penalty than the
            // center proximity bonus.
            if checkPotentialThreat(player: opponent, threat: .openThree, position: move, on: boardToCheck) {
                score -= 2000 // Large penalty for creating an O3
            }
        }
        // --- End Tie-Breaking ---

        // Basic adjacency bonus (very low priority, applied AFTER proximity)
        if isAdjacentToAnyPiece(position: move, on: boardToCheck) {
            score += 1 // Minimal bonus, mainly helps if proximity is also tied
        }

        // print("Static Eval V6: \(move) final score = \(score)") // DEBUG
        return score
    }

    // --- Keep `checkPotentialThreat` helper ---
    func checkPotentialThreat(player: Player, threat: ThreatType, position: Position, on boardToCheck: [[CellState]]) -> Bool {
        // ... (Keep the implementation from previous step) ...
        guard checkBounds(row: position.row, col: position.col) &&
              boardToCheck[position.row][position.col] == .empty else { return false }

        var tempBoard = boardToCheck
        tempBoard[position.row][position.col] = state(for: player)

        return checkForThreatOnBoard(boardToCheck: tempBoard, player: player, threat: threat, lastMove: position)
    }

    // --- NEW Helper for Adjacency Bonus ---
    func isAdjacentToAnyPiece(position: Position, on boardToCheck: [[CellState]]) -> Bool {
         let directions = [(-1,-1), (-1,0), (-1,1), (0,-1), (0,1), (1,-1), (1,0), (1,1)]
         for (dr, dc) in directions {
             let nr = position.row + dr
             let nc = position.col + dc
             if checkBounds(row: nr, col: nc) && boardToCheck[nr][nc] != .empty {
                 return true
             }
         }
         return false
    }
    
    // --- NEW Helper for small depth bias ---
    // Returns a small value based on remaining depth to encourage faster wins/delayed losses
    func depthBias() -> Int {
        // This function needs access to the 'depth' variable from minimax.
        // This requires refactoring minimax slightly or passing depth down.
        // For simplicity *now*, let's return 0. We can add this later if needed.
        return 0
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
    func placeAiPieceAndEndTurn(at position: Position) { guard checkBounds(row: position.row, col: position.col) && board[position.row][position.col] == .empty else { print("!!! AI INTERNAL ERROR: placeAiPieceAndEndTurn called with invalid position \(position). Current: \(board[position.row][position.col])"); let recoveryMove = findEmptyCells(on: self.board).randomElement(); if let move = recoveryMove { print("!!! AI RECOVERY: Placing random piece at \(move) instead."); placePiece(atRow: move.row, col: move.col) } else { print("!!! AI RECOVERY FAILED: No empty cells left?"); view.isUserInteractionEnabled = true }; return }; playSound(key: "place"); softImpactFeedbackGenerator.impactOccurred(); placePiece(atRow: position.row, col: position.col) }
    func checkPotentialWin(player: Player, position: Position, on boardToCheck: [[CellState]]) -> Bool {
        var tempBoard = boardToCheck;
        guard checkBounds(row: position.row, col: position.col) && tempBoard[position.row][position.col] == .empty else { return false };
        tempBoard[position.row][position.col] = state(for: player);
        return checkForWinOnBoard(boardToCheck: tempBoard, playerState: tempBoard[position.row][position.col], lastRow: position.row, lastCol: position.col)
    }
    // Keep original for easy/medium
    func checkPotentialWin(player: Player, position: Position) -> Bool {
        return checkPotentialWin(player: player, position: position, on: self.board)
    }
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
        shapeLayer.strokeColor = UIColor.red.withAlphaComponent(0.88).cgColor // Slightly less transparent
        shapeLayer.lineWidth = 5.5 // <-- Increased thickness
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        shapeLayer.name = "winningLine"
        shapeLayer.shadowColor = UIColor.black.withAlphaComponent(0.4).cgColor // NEW: Softer shadow
        shapeLayer.shadowOffset = CGSize(width: 0, height: 1.5) // NEW
        shapeLayer.shadowRadius = 2.5 // NEW
        shapeLayer.shadowOpacity = 0.8 // NEW

        // Animate the line drawing
        shapeLayer.strokeEnd = 0.0
        boardView.layer.addSublayer(shapeLayer)
        self.winningLineLayer = shapeLayer
        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = 0.0
        animation.toValue = 1.0
        animation.duration = 0.35 // Slightly faster
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut) // Ease out feels better here
        shapeLayer.strokeEnd = 1.0
        shapeLayer.add(animation, forKey: "drawLineAnimation")

        print("Winning line drawn.")

        // --- MODIFIED: Highlight Winning Pieces ---
        let pulseDuration = 0.25
        let numberOfPulses = 3 // How many times to pulse

        // Small delay to let the line draw first
        DispatchQueue.main.asyncAfter(deadline: .now() + animation.duration * 0.7) { [weak self] in // Start slightly before line finishes
            guard let self = self else { return }
            for position in positions {
                if self.checkBounds(row: position.row, col: position.col),
                   let pieceView = self.pieceViews[position.row][position.col] {

                    // Ensure animations start from identity
                    pieceView.layer.removeAllAnimations()
                    pieceView.transform = .identity
                    pieceView.alpha = 1.0
                    pieceView.layer.zPosition = 100

                    // Pulse animation
                    UIView.animateKeyframes(withDuration: pulseDuration * Double(numberOfPulses), delay: 0, options: [.calculationModeLinear, .allowUserInteraction], animations: {
                        for i in 0..<numberOfPulses {
                             UIView.addKeyframe(withRelativeStartTime: Double(i) / Double(numberOfPulses), relativeDuration: 0.5 / Double(numberOfPulses)) {
                                 pieceView.transform = CGAffineTransform(scaleX: 1.25, y: 1.25) // Slightly larger pulse
                                 pieceView.alpha = 0.60 // More noticeable alpha change
                                 // Add a temporary "glow" effect using shadow
                                 pieceView.layer.shadowColor = (self.board[position.row][position.col] == .black) ? UIColor.gray.cgColor : UIColor.white.cgColor
                                 pieceView.layer.shadowRadius = 8
                                 pieceView.layer.shadowOpacity = 0.85
                             }
                             UIView.addKeyframe(withRelativeStartTime: (Double(i) + 0.5) / Double(numberOfPulses), relativeDuration: 0.5 / Double(numberOfPulses)) {
                                 pieceView.transform = .identity
                                 pieceView.alpha = 1.0
                                 // Reset shadow to original piece shadow
                                 pieceView.layer.shadowColor = UIColor.black.cgColor
                                 pieceView.layer.shadowOpacity = 0.30; // Original from drawPiece
                                 pieceView.layer.shadowRadius = 2.5;   // Original from drawPiece
                             }
                        }
                    }) { _ in
                        // Completion block ensures it returns to normal *after* the pulses
                        // Add a slight delay to ensure the last reversal completes
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            // Check if view still exists and reset definitely
                             if self.pieceViews[position.row][position.col] === pieceView {
                                  pieceView.layer.zPosition = 0
                                  pieceView.layer.shadowColor = UIColor.black.cgColor
                                  pieceView.layer.shadowOpacity = 0.30;
                                  pieceView.layer.shadowOffset = CGSize(width: 0.75, height: 1.25);
                                  pieceView.layer.shadowRadius = 2.5;
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
        lightImpactFeedbackGenerator.impactOccurred() // Haptic feedback
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
             print("Resetting game... Requesting AI cancellation.")
             aiShouldCancelMove = true // <-- SET FLAG HERE
             // The minimax check below should cause the AI calc to stop soon

             setupNewGame() // Reset board, player, etc.

             // Re-enable interaction if it's now human's turn (should always be after reset)
             if !isAiTurn {
                 view.isUserInteractionEnabled = true
                 print("Reset complete, interaction enabled for human.")
             } else {
                 // This case shouldn't happen if reset forces black's turn
                 print("Reset complete, but it's still AI's turn? Enabling interaction as failsafe.")
                 view.isUserInteractionEnabled = true
             }
        } else {
             print("Reset tapped while in setup state - doing nothing.")
        }
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpInside)
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchUpOutside)
        sender.removeTarget(self, action: #selector(self.resetButtonReleased(_:)), for: .touchCancel)
    }

} // End of ViewController class

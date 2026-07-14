import SwiftUI

// MARK: - 暗色主题颜色
extension Color {
    static let mmBackground = Color(NSColor(red: 0.06, green: 0.07, blue: 0.09, alpha: 1))       // #0f1117
    static let mmSurface   = Color(NSColor(red: 0.10, green: 0.11, blue: 0.15, alpha: 1))       // #1a1d27
    static let mmSurfaceHover = Color(NSColor(red: 0.12, green: 0.13, blue: 0.19, alpha: 1))    // #1e2130
    static let mmBorder    = Color(NSColor(red: 0.16, green: 0.18, blue: 0.23, alpha: 1))       // #2a2d3a
    static let mmText      = Color(NSColor(red: 0.88, green: 0.89, blue: 0.92, alpha: 1))       // #e1e4eb
    static let mmSecondary = Color(NSColor(red: 0.55, green: 0.56, blue: 0.64, alpha: 1))       // #8b8fa3
    static let mmDim       = Color(NSColor(red: 0.35, green: 0.36, blue: 0.42, alpha: 1))       // #5a5d6a
    static let mmAccent    = Color(NSColor(red: 0.42, green: 0.55, blue: 1.0, alpha: 1))        // #6c8cff
}

// MARK: - 心智模型数据模型
struct MentalModel: Codable, Identifiable {
    var id: String? { mentalModelId ?? name ?? UUID().uuidString }
    let mentalModelId: String?
    let name: String?
    let content: String?
    let tags: [String]?
    let sourceQuery: String?
    let updatedAt: String?
    
    enum CodingKeys: String, CodingKey {
        case mentalModelId = "mental_model_id"
        case name, content, tags
        case sourceQuery = "source_query"
        case updatedAt = "updated_at"
    }
}

// MARK: - 心智模型列表视图
struct MentalModelListView: View {
    @State private var mentalModels: [MentalModel] = []
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(Color.mmAccent)
                    Text("加载心智模型...")
                        .font(.caption)
                        .foregroundStyle(Color.mmSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mmBackground)
            } else if let err = errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(Color.mmSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mmBackground)
            } else if mentalModels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.largeTitle)
                        .foregroundStyle(Color.mmDim)
                    Text("暂无心智模型")
                        .font(.caption)
                        .foregroundStyle(Color.mmSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.mmBackground)
            } else {
                // 全部标签栏（仅显示总数）
                HStack {
                    Text("全部 (\(mentalModels.count))")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.mmAccent)
                        .foregroundStyle(.white)
                        .cornerRadius(7)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.mmSurface.opacity(0.6))
                
                Divider().overlay(Color.mmBorder)
                
                // 列表
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if mentalModels.isEmpty {
                            Text("暂无")
                                .font(.caption)
                                .foregroundStyle(Color.mmDim)
                                .padding(40)
                        }
                        ForEach(mentalModels) { mm in
                            MentalModelRow(mm: mm)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    openDetailWindow(for: mm)
                                }
                        }
                    }
                    .padding(8)
                }
                .background(Color.mmBackground)
            }
        }
        .background(Color.mmBackground)
        .task {
            await loadMentalModels()
        }
    }
    
    private func openDetailWindow(for mm: MentalModel) {
        let detailView = MentalModelDetailView(mm: mm)
        let controller = NSHostingController(rootView: detailView)
        let window = NSWindow(contentViewController: controller)
        window.title = mm.name ?? "详情"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 450, height: 500))
        window.appearance = NSAppearance(named: .darkAqua)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func loadMentalModels() async {
        isLoading = true
        errorMessage = nil
        guard let url = URL(string: "http://localhost:9077/v1/default/banks/hermes/mental-models") else {
            errorMessage = "URL 无效"
            isLoading = false
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                mentalModels = json.compactMap { try? JSONDecoder().decode(MentalModel.self, from: JSONSerialization.data(withJSONObject: $0)) }
            } else if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let items = json["items"] as? [[String: Any]] {
                mentalModels = items.compactMap { try? JSONDecoder().decode(MentalModel.self, from: JSONSerialization.data(withJSONObject: $0)) }
            }
        } catch {
            errorMessage = "加载失败: \(error.localizedDescription)"
        }
        isLoading = false
    }
}

// MARK: - 心智模型行
struct MentalModelRow: View {
    let mm: MentalModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // 小图标
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.mmAccent)
                    .frame(width: 20)
                Text(mm.name ?? "未命名")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.mmText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.mmDim)
            }
            if let content = mm.content, !content.isEmpty {
                Text(content.replacingOccurrences(of: "#", with: "").prefix(150) + "...")
                    .font(.caption)
                    .foregroundStyle(Color.mmSecondary)
                    .lineLimit(2)
                    .padding(.leading, 26)
            }
            if let tags = mm.tags {
                HStack(spacing: 4) {
                    ForEach(tags.filter { !$0.hasPrefix("category:") }, id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.mmAccent.opacity(0.12))
                            .cornerRadius(4)
                            .foregroundStyle(Color.mmAccent)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(10)
        .background(Color.mmSurface)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.mmBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - 心智模型详情
struct MentalModelDetailView: View {
    let mm: MentalModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.mmAccent)
                Text(mm.name ?? "详情")
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundStyle(Color.mmText)
                Spacer()
                Button(action: { NSApp.keyWindow?.close() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(Color.mmDim)
                }
                .buttonStyle(.plain)
                .help("关闭")
                .keyboardShortcut(.escape)
            }
            .padding()
            
            Divider().overlay(Color.mmBorder)
            
            // 内容
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let content = mm.content {
                        Text(content)
                            .font(.body)
                            .foregroundStyle(Color.mmText)
                            .textSelection(.enabled)
                    }
                    
                    if let tags = mm.tags, !tags.isEmpty {
                        Divider().overlay(Color.mmBorder)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("标签")
                                .font(.caption)
                                .foregroundStyle(Color.mmDim)
                            HStack(spacing: 6) {
                                ForEach(tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption2)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.mmAccent.opacity(0.12))
                                        .cornerRadius(4)
                                        .foregroundStyle(Color.mmAccent)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color.mmBackground)
        .frame(width: 450, height: 500)
    }
}

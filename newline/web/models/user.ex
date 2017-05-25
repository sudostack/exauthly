defmodule Newline.User do
  use Newline.Web, :model

  alias Newline.Repo
  import Comeonin.Bcrypt, only: [checkpw: 2, dummy_checkpw: 0]
  # import Newline.BasePolicy, only: [member?: 2]
  import Newline.Helpers.Validation

  @derive {Poison.Encoder, only: [:email, :name, :admin]}
  schema "users" do
    field :name, :string
    field :email, :string

    field :password, :string, virtual: true
    field :encrypted_password, :string

    field :role, :string, default: "user"
    field :admin, :boolean, default: false
    
    field :password_reset_token, :string
    field :password_reset_timestamp, Timex.Ecto.DateTime

    field :verified, :boolean, default: false
    field :verify_token, :string

    has_many :organization_memberships, Newline.OrganizationMembership, foreign_key: :member_id
    has_many :organizations, through: [:organization_memberships, :organization]
    belongs_to :current_organization, Newline.Organization

    timestamps()
  end

  @valid_name_length [min: 1, max: 64]
  @valid_password_length [min: 5, max: 128]
  @valid_roles ~w(user admin superadmin)

  def valid_name_length, do: @valid_name_length
  def valid_roles, do: @valid_roles

  @doc """
  Builds a changeset based on the `struct` and `params`.
  """
  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:name, :email])
    |> validate_required([:email])
    |> validate_email_format(:email)
    |> update_change(:email, &String.downcase/1)
    |> unique_constraint(:email, message: "Email already taken")
    |> generate_encrypted_password
    |> put_token(:verify_token)
  end

  # When a user signs up
  def signup_changeset(user, params \\ %{}) do
    user
    |> __MODULE__.changeset(params)
    |> cast(params, [:password])
    |> validate_required([:password])
    |> validate_length(:password, @valid_password_length)
  end

  # When a user requests a password reset
  def reset_password_request_changeset(user, params \\ %{}) do
    user
    |> cast(params, [:email])
    |> validate_required([:email])
    |> put_change(:password_reset_timestamp, Timex.now)
    |> put_token(:password_reset_token)
  end

  # When a user comes back with a token
  def reset_password_changeset(user, params \\ %{}) do
    user
    |> cast(params, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 5, max: 128)
    |> put_change(:password_reset_token, nil)
    |> put_change(:password_reset_timestamp, nil)
    |> generate_encrypted_password
  end

  @doc """
  Changeset for updating a user's password
  """
  def change_password_changeset(user, params \\ %{}) do
    user
    |> cast(params, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 5, max: 128)
    |> generate_encrypted_password
  end

  def verifying_changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:verify_token])
    |> validate_required([:verify_token])
    |> put_change(:verified, true)
    |> put_change(:verify_token, nil)
  end

  # When a user is getting updated
  def update_changeset(user, params \\ %{}) do
    user
    |> cast(params, [:name, :email, :admin, :role, :current_organization_id])
    |> update_change(:email, &String.downcase/1)
    |> validate_email_format(:email)
    |> unique_constraint(:email, message: "Email already taken")
    |> validate_inclusion(:role, @valid_roles)
    |> foreign_key_constraint(:current_organization_id)
    |> assoc_constraint(:current_organization)
    |> validate_can_switch_to_organization
  end

  defp validate_can_switch_to_organization(changeset) do
    # Only run our validation if there are changes and no previous errors
    user_id = get_field(changeset, :id)
    if changeset.valid? && changeset.changes != %{} && user_id != nil do
      current_org_id = get_field(changeset, :current_organization_id)

      memberships = user_group_ids(user_id)
      case Enum.member?(memberships, current_org_id) do
        true -> changeset
        false -> Ecto.Changeset.add_error(changeset, :current_organization_id, "must be a member to switch to this organization")
      end
      changeset
    else
      changeset
    end
  end

  defp user_group_ids(user_id) do
    membership_query = from m in Newline.OrganizationMembership,
                        where: m.member_id == ^user_id,
                        left_join: org in assoc(m, :organization),
                        select: org.id
    Repo.all(membership_query)
  end

  def authenticate_by_email_and_pass(%{email: email, password: password} = _params) do
    user = Repo.get_by(Newline.User, email: String.downcase(email))
    cond do
      check_user_password(user, password) -> {:ok, user}
      user ->
        {:error, "Your password does not match with the password we have on record"}
      true ->
        dummy_checkpw()
        {:error, "We couldn't find a user associated with the email #{email}"}
    end
  end
  def authenticate_by_email_and_pass(_), do: {:error, "bad_credentials"}

  @doc """
  Check a user's password with bcrypt'
  """
  def check_user_password(user, password) do
    user && checkpw(password, user.encrypted_password)
  end

  # Helpers
  defp generate_encrypted_password(current_changeset) do
    case current_changeset do
      %Ecto.Changeset{valid?: true, changes: %{password: password}} ->
        put_change(current_changeset, :encrypted_password, Comeonin.Bcrypt.hashpwsalt(password))
      _ ->
        current_changeset
    end
  end

  # Token
  defp put_token(changeset, field) do
    case changeset do
      %Ecto.Changeset{valid?: true} ->
        # Valid changeset
        token = generate_token()
        put_change(changeset, field, token)
      _ ->
        changeset
    end
  end

  defp generate_token do
    50
    |> :crypto.strong_rand_bytes
    |> Base.url_encode64
    |> binary_part(0, 50)
  end

end
